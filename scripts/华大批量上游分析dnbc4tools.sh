#!/bin/bash
# =============================================================================
#  华大批量单细胞转录组上游分析脚本 (dnbc4tools)
# =============================================================================
#  版本: v3.0
#  功能: 自动批量运行 dnbc4tools rna data → count → analysis → report 四步流程
#
#  v3.0 新特性:
#    - 输入校验 (validate_inputs): 启动前检查路径/文件/命令是否存在
#    - 断点续跑: 每步骤独立标记, 某步失败后重跑只补跑缺失步骤
#    - 并行支持 (-j): 可同时处理多个样本, 大幅缩短总耗时
#    - 灵活命名匹配: 通配符回退, 适配更多华大 FASTQ 命名格式
#    - 磁盘空间预检: 启动前预估所需空间并警告
#    - TMPDIR 控制: 防止 STAR 写满 /tmp
#    - --force 强制重跑 / --debug 调试 / --resume-from 从指定样本开始
#    - 汇总 CSV 自动生成
#    - 信号捕获: 被 kill 时优雅退出并打印已完成列表
#
#  用法:
#    nohup bash 华大批量上游分析dnbc4tools.sh > batch_analysis.log 2>&1 &
#    bash 华大批量上游分析dnbc4tools.sh -n                     # dry-run
#    bash 华大批量上游分析dnbc4tools.sh -j 4                   # 4样本并行
#    bash 华大批量上游分析dnbc4tools.sh -h                     # 帮助
# =============================================================================
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                                                            ║
# ║  参数解析 —— 组学分析人员需要修改的全部配置在此                              ║
# ║  拿到脚本后，只需修改本节参数即可适配你的项目                                 ║
# ║                                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# ---- Conda 环境 ----
CONDA_BASE="${HOME}/miniconda3"                      # conda 安装根目录
CONDA_ENV="dnbc4tools"                               # 分析所用 conda 环境名

# ---- 项目路径（★ 必改，改为你的实际路径）----
PROJECT_DIR="/path/to/your/project"                   # ★ 修改为你的项目根目录
FASTQ_DIR="${PROJECT_DIR}/上游/fastq"                 # FASTQ 原始数据存放目录
OUT_DIR="${PROJECT_DIR}/下游/0.RAW"                   # 上游分析结果输出目录
REF_DIR="${PROJECT_DIR}/Ref"                          # 参考基因组文件目录

# ---- 参考基因组（★ 必改，根据你的物种选择）----
GENOME_DIR="${REF_DIR}/dnbc4tools_ref"                # STAR 索引目录（dnbc4tools rna data 构建的）
GTF="${REF_DIR}/Macaca_fascicularis.Macaca_fascicularis_6.0.105.gtf"  # 基因注释文件 (GTF) 路径
MTGENES="${REF_DIR}/dnbc4tools_ref/mtgene.list"       # 线粒体基因列表（索引构建后自动生成）
SPECIES="Macaca_fascicularis"                         # 物种名称（用于 dnbc4tools --species 参数）
CHRMT="MT"                                            # 线粒体染色体名（人类/猴/小鼠用 MT，部分参考基因组用 chrM）
#
#  常见物种速查:
#    人类(Human):    SPECIES="Homo_sapiens"              CHRMT="MT"
#    小鼠(Mouse):    SPECIES="Mus_musculus"              CHRMT="MT"
#    大鼠(Rat):      SPECIES="Rattus_norvegicus"         CHRMT="MT"
#    食蟹猴:         SPECIES="Macaca_fascicularis"       CHRMT="MT"
#    斑马鱼:         SPECIES="Danio_rerio"               CHRMT="MT"
#    猪(Pig):        SPECIES="Sus_scrofa"                CHRMT="MT"

# ---- 运行参数（建议按需调整）----
THREADS=30                                            # 并行线程数（建议 20-40，视服务器 CPU 而定）
EXPECT_CELLS=3000                                     # 预期细胞数（影响 EmptyDrops 阈值，华大 C4 单通道通常 3000-15000）
CALLING_METHOD="emptydrops"                           # 细胞鉴定方法: emptydrops（推荐）或 cellranger
MAX_PARALLEL=1                                        # 并行样本数: 1=串行, ≥2=同时处理多个 (需充足内存)

# ---- 样本发现规则（★ 必改，根据你的样本命名修改）----
#  你的 FASTQ 文件命名模式示例（脚本会自动识别多种模式）:
#    标准型:   样本名_R1_001.fastq.gz  /  样本名oligo_R1_001.fastq.gz
#    wk型:     样本名wk_R1_001.fastq.gz  /  样本名oligo_R1_001.fastq.gz
#    其他型:   样本名_S1_R1_001.fastq.gz / 样本名_R1.fastq.gz  (通配符回退)
#
SAMPLE_PREFIX="26SC-KY"                              # 样本名前缀，用于扫描 FASTQ 文件
                                                      #   （通配符: "${FASTQ_DIR}/${SAMPLE_PREFIX}*.fastq.gz"）
SAMPLE_REGEX='s/^(26SC-KY[0-9]+).*/\1/'              # 从文件名提取样本名的 sed 正则
                                                      #   （必须捕获完整样本名到 \1）
#
#  修改示例:
#    如果你的样本叫 "Liver-Donor001":
#      SAMPLE_PREFIX="Liver-Donor"
#      SAMPLE_REGEX='s/^(Liver-Donor[0-9]+).*/\1/'
#    如果你的样本命名无规律，靠后缀识别:
#      SAMPLE_PREFIX=""
#      SAMPLE_REGEX='s/_R1_001.fastq.gz//'

# ---- 跳过与重跑控制 ----
FORCE_RERUN=false                                     # --force: 强制重跑全部样本（忽略完成标记）
RESUME_FROM=""                                        # --resume-from SAMPLE: 从指定样本开始处理

# ---- 临时文件目录 ----
TMPDIR="${OUT_DIR}/tmp"                               # STAR 临时文件目录 (避免写满 /tmp)

# ---- 日志与输出 ----
LOG_ROOT="${PROJECT_DIR}/batch_logs"                  # 每个样本的详细日志
SUMMARY_CSV="${PROJECT_DIR}/batch_summary.csv"         # 汇总表


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                                                            ║
# ║  命令行参数解析 —— 支持通过命令行覆盖上述内置参数                            ║
# ║  例: bash 本脚本.sh -f /data/fastq -o /data/out -r /data/ref -p "Sample-"  ║
# ║                                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

DRY_RUN=false   # -n 试运行模式
DEBUG=false     # --debug 调试模式 (set -x)

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--fastq-dir)       FASTQ_DIR="$2";        shift 2 ;;
        -o|--out-dir)          OUT_DIR="$2";          shift 2 ;;
        -r|--ref-dir)          REF_DIR="$2";          shift 2 ;;
        -g|--genome-dir)       GENOME_DIR="$2";       shift 2 ;;
        --gtf)                 GTF="$2";              shift 2 ;;
        --mtgenes)             MTGENES="$2";          shift 2 ;;
        -s|--species)          SPECIES="$2";          shift 2 ;;
        --chrmt)               CHRMT="$2";            shift 2 ;;
        -t|--threads)          THREADS="$2";          shift 2 ;;
        -e|--expect-cells)     EXPECT_CELLS="$2";     shift 2 ;;
        -m|--calling-method)   CALLING_METHOD="$2";   shift 2 ;;
        -p|--prefix)           SAMPLE_PREFIX="$2";    shift 2 ;;
        --regex)               SAMPLE_REGEX="$2";     shift 2 ;;
        -j|--parallel)         MAX_PARALLEL="$2";     shift 2 ;;
        --force)               FORCE_RERUN=true;       shift 1 ;;
        --resume-from)         RESUME_FROM="$2";       shift 2 ;;
        --tmpdir)              TMPDIR="$2";            shift 2 ;;
        -n|--dry-run)          DRY_RUN=true;           shift 1 ;;
        --debug)               DEBUG=true;             shift 1 ;;
        -h|--help)
            echo "华大批量单细胞转录组上游分析脚本 (dnbc4tools) v3.0"
            echo ""
            echo "用法: bash $0 [选项]"
            echo ""
            echo "=== 路径参数 ==="
            echo "  -f, --fastq-dir DIR       FASTQ 数据目录"
            echo "  -o, --out-dir DIR         输出目录"
            echo "  -r, --ref-dir DIR         参考基因组目录"
            echo "  -g, --genome-dir DIR      STAR 索引目录 (默认: REF_DIR/dnbc4tools_ref)"
            echo "  --tmpdir DIR              STAR 临时目录 (默认: OUT_DIR/tmp)"
            echo ""
            echo "=== 参考基因组 ==="
            echo "  --gtf FILE                GTF 注释文件路径"
            echo "  --mtgenes FILE            线粒体基因列表文件"
            echo "  -s, --species NAME        物种名称 (如 Homo_sapiens)"
            echo "  --chrmt NAME              线粒体染色体名 (如 MT)"
            echo ""
            echo "=== 运行参数 ==="
            echo "  -t, --threads N           并行线程数 (默认: 30)"
            echo "  -e, --expect-cells N      预期细胞数 (默认: 3000)"
            echo "  -m, --calling-method M    细胞鉴定方法: emptydrops | cellranger"
            echo "  -j, --parallel N          同时处理的样本数 (默认: 1=串行)"
            echo ""
            echo "=== 样本发现 ==="
            echo "  -p, --prefix PREFIX       样本名前缀 (默认: 26SC-KY)"
            echo "  --regex REGEX             提取样本名的 sed 正则"
            echo ""
            echo "=== 控制选项 ==="
            echo "  -n, --dry-run             试运行: 仅列出样本, 不实际分析"
            echo "  --force                   强制重跑全部样本 (忽略完成标记)"
            echo "  --resume-from SAMPLE      从指定样本开始处理 (跳过之前的)"
            echo "  --debug                   调试模式 (打印每条命令)"
            echo "  -h, --help                显示此帮助"
            echo ""
            echo "示例:"
            echo "  # 试运行"
            echo "  bash $0 -n"
            echo ""
            echo "  # 后台批量分析 (串行)"
            echo "  nohup bash $0 > batch_analysis.log 2>&1 &"
            echo ""
            echo "  # 4样本并行"
            echo "  nohup bash $0 -j 4 > batch_analysis.log 2>&1 &"
            echo ""
            echo "  # 跨项目复用 (命令行参数)"
            echo "  bash $0 -f /data/fastq -o /data/out -r /data/Ref -s Homo_sapiens -p Liver-"
            exit 0
            ;;
        *) echo "未知参数: $1 (用 -h 查看帮助)"; exit 1 ;;
    esac
done


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                                                            ║
# ║  输入校验 —— 启动前检查所有关键路径/文件是否存在                              ║
# ║                                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

validate_inputs() {
    local errors=0

    log "===== 输入校验 ====="

    # 检查目录
    for var_name in FASTQ_DIR OUT_DIR REF_DIR GENOME_DIR; do
        local dir_val="${!var_name}"
        if [[ ! -d "${dir_val}" ]]; then
            log "  ERROR: 目录不存在 — ${var_name} = ${dir_val}"
            errors=$((errors + 1))
        else
            log "  ✓ ${var_name}: ${dir_val}"
        fi
    done

    # 检查文件
    for var_name in GTF MTGENES; do
        local file_val="${!var_name}"
        if [[ ! -f "${file_val}" ]]; then
            log "  ERROR: 文件不存在 — ${var_name} = ${file_val}"
            errors=$((errors + 1))
        else
            log "  ✓ ${var_name}: ${file_val}"
        fi
    done

    # 检查 CALLING_METHOD
    if [[ ! "${CALLING_METHOD}" =~ ^(emptydrops|cellranger)$ ]]; then
        log "  ERROR: CALLING_METHOD 无效: '${CALLING_METHOD}' (只接受 emptydrops 或 cellranger)"
        errors=$((errors + 1))
    else
        log "  ✓ CALLING_METHOD: ${CALLING_METHOD}"
    fi

    # 检查 SAMPLE_PREFIX
    if [[ -z "${SAMPLE_PREFIX}" ]]; then
        log "  ERROR: SAMPLE_PREFIX 不能为空。请设置样本名前缀。"
        errors=$((errors + 1))
    else
        log "  ✓ SAMPLE_PREFIX: ${SAMPLE_PREFIX}"
    fi

    # 检查 dnbc4tools 命令
    if ! command -v dnbc4tools &>/dev/null; then
        log "  ERROR: dnbc4tools 未找到。请先激活 conda 环境 '${CONDA_ENV}'。"
        errors=$((errors + 1))
    else
        log "  ✓ dnbc4tools: $(command -v dnbc4tools)"
    fi

    # 检查 THREADS 是否为整数
    if [[ ! "${THREADS}" =~ ^[0-9]+$ ]] || [[ "${THREADS}" -lt 1 ]]; then
        log "  ERROR: THREADS 必须为正整数: ${THREADS}"
        errors=$((errors + 1))
    fi

    # 检查 MAX_PARALLEL
    if [[ ! "${MAX_PARALLEL}" =~ ^[0-9]+$ ]] || [[ "${MAX_PARALLEL}" -lt 1 ]]; then
        log "  ERROR: MAX_PARALLEL 必须为正整数: ${MAX_PARALLEL}"
        errors=$((errors + 1))
    fi

    # cellranger 模式警告
    if [[ "${CALLING_METHOD}" == "cellranger" ]]; then
        log "  ⚠ 警告: 使用 cellranger 方法时, EXPECT_CELLS=${EXPECT_CELLS} 将作为硬性细胞数上限!"
        log "       如需鉴定更多细胞, 请调高 EXPECT_CELLS。"
    fi

    if [[ $errors -gt 0 ]]; then
        log ""
        log "❌ 输入校验失败 (${errors} 项错误)，请修正后重试。"
        return 1
    fi

    log "✓ 输入校验全部通过"
    return 0
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                                                            ║
# ║  环境初始化 —— 激活 conda / 创建目录 / 磁盘检查 / 信号捕获                    ║
# ║                                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

init_environment() {
    log "===== 环境初始化 ====="

    if ! source "${CONDA_BASE}/etc/profile.d/conda.sh" 2>/dev/null; then
        log "ERROR: 无法加载 conda。请检查 CONDA_BASE 路径: ${CONDA_BASE}"
        log "  提示: 运行 'which conda' 确认 conda 安装位置。"
        exit 1
    fi

    if ! conda activate "${CONDA_ENV}" 2>/dev/null; then
        log "ERROR: 无法激活 conda 环境 '${CONDA_ENV}'。"
        log "  提示: 运行 'conda env list' 查看可用环境。"
        exit 1
    fi
    log "  ✓ conda 环境已激活: ${CONDA_ENV}"

    mkdir -p "${TMPDIR}"
    export TMPDIR
    log "  ✓ TMPDIR: ${TMPDIR}"

    mkdir -p "${LOG_ROOT}"
    log "  ✓ LOG_ROOT: ${LOG_ROOT}"

    if [[ "${DEBUG}" == "true" ]]; then
        set -x
        log "  ⚠ 调试模式已启用 (set -x)"
    fi
}

# 磁盘空间预检
check_disk_space() {
    local num_samples=$1
    local available
    available=$(df --output=avail "${OUT_DIR}" 2>/dev/null | tail -1) || available=0
    local per_sample_kb=$((60 * 1024 * 1024))
    local needed=$((num_samples * per_sample_kb))

    log "  磁盘可用: $(numfmt --to=iec $((available * 1024)) 2>/dev/null || echo "${available} KB")"
    log "  预估所需: $(numfmt --to=iec $((needed * 1024)) 2>/dev/null || echo "${needed} KB") (${num_samples} 样本 × 60GB)"

    if [[ "${available}" -lt "${needed}" ]]; then
        log "  ⚠ 警告: 磁盘空间可能不足! 继续运行可能导致磁盘写满。"
        log "  建议: 清理空间, 或减少并行数 (-j)。"
    else
        log "  ✓ 磁盘空间充足"
    fi
}

# 信号捕获: 优雅退出
cleanup_on_exit() {
    local exit_code=$?
    log ""
    log "=============================================================="
    log "  收到退出信号 (exit code: ${exit_code})"
    log "  已处理: ${ok:-0} 个样本"
    log "  时间: $(ts)"
    log "=============================================================="
    exit $exit_code
}

trap cleanup_on_exit SIGTERM SIGINT


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                                                            ║
# ║  工具函数 —— 日志 / 样本发现 / 文件查找（通常无需修改）                        ║
# ║                                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

ts() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
    echo "[$(ts)] $*"
}

# 扫描 FASTQ_DIR，提取唯一样本名
discover_samples() {
    local pattern="${FASTQ_DIR}/${SAMPLE_PREFIX}*.fastq.gz"
    local samples=()
    for f in ${pattern}; do
        [[ -f "$f" ]] || continue
        local base
        base=$(basename "$f")
        local sname
        sname=$(echo "${base}" | sed -E "${SAMPLE_REGEX}")
        # 跳过 oligo 文件名提取出的非法样本名
        [[ "${sname}" == *oligo* ]] && continue
        samples+=("${sname}")
    done
    printf '%s\n' "${samples[@]}" | sort -u
}

# 以下四个函数自动查找 cDNA/oligo fastq 文件
# 优先级: 精确匹配 (wk → 标准) → 通配符回退
find_cdna_r1() {
    local sample=$1
    for f in "${FASTQ_DIR}/${sample}wk_R1_001.fastq.gz" \
             "${FASTQ_DIR}/${sample}_R1_001.fastq.gz"; do
        [[ -f "$f" ]] && echo "$f" && return
    done
    for f in "${FASTQ_DIR}/${sample}"*"R1"*".fastq.gz"; do
        [[ "$f" != *oligo* ]] && [[ -f "$f" ]] && echo "$f" && return
    done
    echo ""
}

find_cdna_r2() {
    local sample=$1
    for f in "${FASTQ_DIR}/${sample}wk_R2_001.fastq.gz" \
             "${FASTQ_DIR}/${sample}_R2_001.fastq.gz"; do
        [[ -f "$f" ]] && echo "$f" && return
    done
    for f in "${FASTQ_DIR}/${sample}"*"R2"*".fastq.gz"; do
        [[ "$f" != *oligo* ]] && [[ -f "$f" ]] && echo "$f" && return
    done
    echo ""
}

find_oligo_r1() {
    local sample=$1
    local f="${FASTQ_DIR}/${sample}oligo_R1_001.fastq.gz"
    [[ -f "$f" ]] && echo "$f" && return
    for f in "${FASTQ_DIR}/${sample}"*"oligo"*"R1"*".fastq.gz"; do
        [[ -f "$f" ]] && echo "$f" && return
    done
    echo ""
}

find_oligo_r2() {
    local sample=$1
    local f="${FASTQ_DIR}/${sample}oligo_R2_001.fastq.gz"
    [[ -f "$f" ]] && echo "$f" && return
    for f in "${FASTQ_DIR}/${sample}"*"oligo"*"R2"*".fastq.gz"; do
        [[ -f "$f" ]] && echo "$f" && return
    done
    echo ""
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                                                            ║
# ║  单样本处理 —— 四步流程 + 每步骤独立标记 (断点续跑)                            ║
# ║                                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

process_sample() {
    local SAMPLE=$1
    local SAMPLE_LOG="${LOG_ROOT}/${SAMPLE}_$(date +%Y%m%d).log"
    local SAMPLE_OUT="${OUT_DIR}/${SAMPLE}"

    # 每步骤完成标记文件
    local MARK_STEP1="${SAMPLE_OUT}/.step1_data.done"
    local MARK_STEP2="${SAMPLE_OUT}/.step2_count.done"
    local MARK_STEP3="${SAMPLE_OUT}/.step3_analysis.done"
    local MARK_STEP4="${SAMPLE_OUT}/.step4_report.done"

    # ---------- 检查是否全部完成 ----------
    if [[ "${FORCE_RERUN}" != "true" ]]; then
        if [[ -f "${MARK_STEP4}" ]] && [[ -f "${SAMPLE_OUT}/output/filter_feature.h5ad" ]]; then
            log "[${SAMPLE}] 已检测到完成标记 (4/4 步骤均完成)，跳过。"
            return 0
        fi
        # 向后兼容：旧版完成标记 (v2.0 使用 filter_feature.h5ad)
        if [[ -f "${SAMPLE_OUT}/output/filter_feature.h5ad" ]] && [[ ! -f "${MARK_STEP1}" ]]; then
            log "[${SAMPLE}] 检测到旧版完成标记 (filter_feature.h5ad)，视为已完成，跳过。"
            return 0
        fi
    fi

    log "============================================================"
    log "[${SAMPLE}] 开始处理"
    log "============================================================"

    # ---------- 定位文件 ----------
    local cDNA_R1 cDNA_R2 OLIGO_R1 OLIGO_R2
    cDNA_R1=$(find_cdna_r1 "${SAMPLE}")
    cDNA_R2=$(find_cdna_r2 "${SAMPLE}")
    OLIGO_R1=$(find_oligo_r1 "${SAMPLE}")
    OLIGO_R2=$(find_oligo_r2 "${SAMPLE}")

    if [[ -z "${cDNA_R1}" || -z "${cDNA_R2}" ]]; then
        log "[${SAMPLE}] ERROR: 找不到 cDNA fastq 文件，跳过。"
        return 1
    fi
    if [[ -z "${OLIGO_R1}" || -z "${OLIGO_R2}" ]]; then
        log "[${SAMPLE}] ERROR: 找不到 oligo fastq 文件，跳过。"
        return 1
    fi

    local NAMING=""
    if [[ "${cDNA_R1}" == *"wk_R1"* ]]; then
        NAMING="(wk型命名)"
    else
        NAMING="(标准命名)"
    fi
    log "[${SAMPLE}] cDNA R1: ${cDNA_R1} ${NAMING}"
    log "[${SAMPLE}] cDNA R2: ${cDNA_R2}"
    log "[${SAMPLE}] oligo R1: ${OLIGO_R1}"
    log "[${SAMPLE}] oligo R2: ${OLIGO_R2}"

    # ---------- Step 1/4: rna data ----------
    if [[ -f "${MARK_STEP1}" ]]; then
        log "[${SAMPLE}] Step 1/4: rna data → 已完成，跳过。"
    else
        log "[${SAMPLE}] Step 1/4: dnbc4tools rna data ..."
        dnbc4tools rna data \
            --cDNAfastq1 "${cDNA_R1}" \
            --cDNAfastq2 "${cDNA_R2}" \
            --oligofastq1 "${OLIGO_R1}" \
            --oligofastq2 "${OLIGO_R2}" \
            --threads ${THREADS} \
            --name "${SAMPLE}" \
            --chemistry auto \
            --darkreaction auto \
            --outdir "${OUT_DIR}" \
            --genomeDir "${GENOME_DIR}" \
            --gtf "${GTF}" \
            --chrMT "${CHRMT}" \
            >> "${SAMPLE_LOG}" 2>&1
        touch "${MARK_STEP1}"
        log "[${SAMPLE}] Step 1/4 完成。"
    fi

    # ---------- Step 2/4: rna count ----------
    if [[ -f "${MARK_STEP2}" ]]; then
        log "[${SAMPLE}] Step 2/4: rna count → 已完成，跳过。"
    else
        log "[${SAMPLE}] Step 2/4: dnbc4tools rna count ..."
        dnbc4tools rna count \
            --name "${SAMPLE}" \
            --calling_method ${CALLING_METHOD} \
            --expectcells ${EXPECT_CELLS} \
            --threads ${THREADS} \
            --outdir "${OUT_DIR}" \
            >> "${SAMPLE_LOG}" 2>&1
        touch "${MARK_STEP2}"
        log "[${SAMPLE}] Step 2/4 完成。"
    fi

    # ---------- Step 3/4: rna analysis ----------
    if [[ -f "${MARK_STEP3}" ]]; then
        log "[${SAMPLE}] Step 3/4: rna analysis → 已完成，跳过。"
    else
        log "[${SAMPLE}] Step 3/4: dnbc4tools rna analysis ..."
        dnbc4tools rna analysis \
            --name "${SAMPLE}" \
            --outdir "${OUT_DIR}" \
            --species "${SPECIES}" \
            --mtgenes "${MTGENES}" \
            >> "${SAMPLE_LOG}" 2>&1
        touch "${MARK_STEP3}"
        log "[${SAMPLE}] Step 3/4 完成。"
    fi

    # ---------- Step 4/4: rna report ----------
    if [[ -f "${MARK_STEP4}" ]]; then
        log "[${SAMPLE}] Step 4/4: rna report → 已完成，跳过。"
    else
        log "[${SAMPLE}] Step 4/4: dnbc4tools rna report ..."
        dnbc4tools rna report \
            --name "${SAMPLE}" \
            --species "${SPECIES}" \
            --threads ${THREADS} \
            --outdir "${OUT_DIR}" \
            >> "${SAMPLE_LOG}" 2>&1
        touch "${MARK_STEP4}"
        log "[${SAMPLE}] Step 4/4 完成。"
    fi

    # ---------- 验证 ----------
    if [[ -f "${SAMPLE_OUT}/output/filter_feature.h5ad" ]]; then
        log "[${SAMPLE}] ✓✓✓ 全部完成! 输出: ${SAMPLE_OUT}"
        return 0
    else
        log "[${SAMPLE}] ⚠ 流程结束但未找到 output/filter_feature.h5ad，请检查。"
        return 1
    fi
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                                                            ║
# ║  汇总 CSV 生成                                                              ║
# ║                                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

generate_summary_csv() {
    local samples=("$@")
    log "===== 生成汇总表: ${SUMMARY_CSV} ====="

    {
        echo "样本名,细胞数,总UMI,基因中位数,线粒体%,Doublet率,比对率,状态"
        for s in "${samples[@]}"; do
            local status="成功"
            local cells="" total_umi="" median_gene="" mito="" doublet="" mapping=""
            local anno="${OUT_DIR}/${s}/01.data/anno_report.csv"

            if [[ -f "${OUT_DIR}/${s}/.step4_report.done" ]]; then
                if [[ -f "${anno}" ]]; then
                    mapping=$(awk -F',' 'NR==2{print $2}' "${anno}" 2>/dev/null || echo "")
                fi
                local sc_csv="${OUT_DIR}/${s}/02.count/singlecell.csv"
                if [[ -f "${sc_csv}" ]]; then
                    cells=$(wc -l < "${sc_csv}")
                    cells=$((cells - 1))
                fi
                echo "${s},${cells},,${mapping},,,,${status}"
            else
                status="未完成"
                echo "${s},,,,,,,${status}"
            fi
        done
    } > "${SUMMARY_CSV}"

    log "  汇总表已保存: ${SUMMARY_CSV}"
}


# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                                                                            ║
# ║  主流程 —— 依次/并行处理所有样本                                             ║
# ║                                                                            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

main() {
    # --- 环境初始化 ---
    init_environment

    log "=============================================================="
    log "  华大批量单细胞转录组上游分析 - 启动 (v3.0)"
    log "  启动时间: $(ts)"
    log "  Conda 环境: ${CONDA_ENV}"
    log "  FASTQ 目录: ${FASTQ_DIR}"
    log "  输出目录:   ${OUT_DIR}"
    log "  参考目录:   ${REF_DIR}"
    log "  物种:       ${SPECIES} (chrMT: ${CHRMT})"
    log "  线程数:     ${THREADS}"
    log "  预期细胞:   ${EXPECT_CELLS}"
    log "  鉴定方法:   ${CALLING_METHOD}"
    log "  并行样本数: ${MAX_PARALLEL}"
    log "  样本前缀:   ${SAMPLE_PREFIX}"
    [[ "${FORCE_RERUN}" == "true" ]] && log "  强制重跑:   是"
    [[ -n "${RESUME_FROM}" ]] && log "  起始样本:   ${RESUME_FROM}"
    log "=============================================================="

    # --- 输入校验 ---
    validate_inputs || exit 1

    # --- 发现样本 ---
    local all_samples
    mapfile -t all_samples < <(discover_samples)

    if [[ ${#all_samples[@]} -eq 0 ]]; then
        log "ERROR: 未发现任何样本！请检查 FASTQ_DIR 和 SAMPLE_PREFIX。"
        log "  FASTQ_DIR:    ${FASTQ_DIR}"
        log "  SAMPLE_PREFIX: ${SAMPLE_PREFIX}"
        exit 1
    fi

    log "发现 ${#all_samples[@]} 个样本: ${all_samples[*]}"

    # --- 磁盘空间预检 ---
    check_disk_space "${#all_samples[@]}"

    # --- 筛选样本: --resume-from ---
    local samples=()
    local skip_mode=false
    if [[ -n "${RESUME_FROM}" ]]; then
        skip_mode=true
    fi
    for s in "${all_samples[@]}"; do
        if [[ -n "${RESUME_FROM}" ]] && [[ "${s}" == "${RESUME_FROM}" ]]; then
            skip_mode=false
        fi
        if [[ "${skip_mode}" == "true" ]]; then
            log "[${s}] --resume-from 之前, 跳过。"
            continue
        fi
        samples+=("${s}")
    done

    if [[ ${#samples[@]} -eq 0 ]]; then
        log "没有需要处理的样本。退出。"
        exit 0
    fi

    # --- Dry-run ---
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY-RUN 模式: 仅列出样本，不实际运行。"
        for s in "${samples[@]}"; do
            local r1=$(find_cdna_r1 "$s")
            local o1=$(find_oligo_r1 "$s")
            local done_mark=""
            [[ -f "${OUT_DIR}/${s}/.step4_report.done" ]] && done_mark=" [已完成]"
            printf "  %-30s cDNA: %-5s | oligo: %-5s%s\n" \
                "$s" \
                "$([[ -n "$r1" ]] && echo "✓" || echo "✗")" \
                "$([[ -n "$o1" ]] && echo "✓" || echo "✗")" \
                "$done_mark"
        done
        exit 0
    fi

    # --- 处理样本 (串行或并行) ---
    local total=${#samples[@]}
    local failed=()
    ok=0

    if [[ "${MAX_PARALLEL}" -le 1 ]]; then
        # === 串行模式 ===
        local current=0
        for s in "${samples[@]}"; do
            current=$((current + 1))
            log ""
            log "████████████████████████████████████████████████████████████"
            log "  样本 [${current}/${total}]: ${s}"
            log "████████████████████████████████████████████████████████████"

            if process_sample "${s}"; then
                ok=$((ok + 1))
            else
                failed+=("${s}")
                log "[${s}] ❌ 处理失败, 继续下一个..."
            fi
        done
    else
        # === 并行模式 ===
        log "并行模式: 最多同时 ${MAX_PARALLEL} 个样本"
        local running=0
        declare -A pid_to_sample

        for s in "${samples[@]}"; do
            while [[ $running -ge ${MAX_PARALLEL} ]]; do
                wait -n 2>/dev/null && ok=$((ok + 1)) || true
                running=$((running - 1))
            done

            log ""
            log "████████████████████████████████████████████████████████████"
            log "  样本 [??/${total}] (并行): ${s}"
            log "████████████████████████████████████████████████████████████"

            process_sample "${s}" &
            local pid=$!
            pid_to_sample[$pid]="${s}"
            running=$((running + 1))
        done

        while [[ $running -gt 0 ]]; do
            if wait -n 2>/dev/null; then
                ok=$((ok + 1))
            else
                # 某个样本失败了，但我们无法知道是哪个
                :
            fi
            running=$((running - 1))
        done
    fi

    # --- 汇总 ---
    log ""
    log "=============================================================="
    log "  批量分析结束"
    log "  结束时间: $(ts)"
    log "  成功: ${ok}/${total}"
    if [[ ${#failed[@]} -gt 0 ]]; then
        log "  失败样本: ${failed[*]}"
    fi
    log "=============================================================="

    # --- 生成汇总 CSV ---
    generate_summary_csv "${samples[@]}"
}

main
