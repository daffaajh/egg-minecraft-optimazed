#!/bin/bash
#
# YuraCloud CPU Faker - Override /proc/cpuinfo dengan AMD EPYC 7232P
# Script ini generate fake cpuinfo based on real core count tapi dengan CPU model fake
#

FAKE_CPUINFO="/tmp/cpuinfo_fake"
REAL_CPUINFO="/proc/cpuinfo"

# Fake CPU specs - AMD EPYC 7232P
FAKE_MODEL="AMD EPYC 7232P 8-Core Processor"
FAKE_VENDOR="AuthenticAMD"
FAKE_FAMILY="23"
FAKE_MODEL_NUM="49"
FAKE_STEPPING="0"
FAKE_MHZ="3200.000"
FAKE_CACHE="16384 KB"
FAKE_BOGOMIPS="6400.00"

# Get real core count from actual cpuinfo
REAL_CORES=$(grep -c "^processor" "$REAL_CPUINFO")

# Generate fake cpuinfo dengan core count real tapi specs fake
{
  for ((i=0; i<REAL_CORES; i++)); do
    cat <<EOF
processor	: $i
vendor_id	: $FAKE_VENDOR
cpu family	: $FAKE_FAMILY
model		: $FAKE_MODEL_NUM
model name	: $FAKE_MODEL
stepping	: $FAKE_STEPPING
microcode	: 0x8301055
cpu MHz		: $FAKE_MHZ
cache size	: $FAKE_CACHE
physical id	: 0
siblings	: $REAL_CORES
core id		: $i
cpu cores	: $REAL_CORES
apicid		: $i
initial apicid	: $i
fpu		: yes
fpu_exception	: yes
cpuid level	: 16
wp		: yes
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl nonstop_tsc cpuid extd_apicid aperfmperf rapl pni pclmulqdq monitor ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand lahf_lm cmp_legacy svm extapic cr8_legacy abm sse4a misalignsse 3dnowprefetch osvw ibs skinit wdt tce topoext perfctr_core perfctr_nb bpext perfctr_llc mwaitx cpb cat_l3 cdp_l3 hw_pstate ssbd mba ibrs ibpb stibp vmmcall fsgsbase bmi1 avx2 smep bmi2 cqm rdt_a rdseed adx smap clflushopt clwb sha_ni xsaveopt xsavec xgetbv1 xsaves cqm_llc cqm_occup_llc cqm_mbm_total cqm_mbm_local clzero irperf xsaveerptr rdpru wbnoinvd arat npt lbrv svm_lock nrip_save tsc_scale vmcb_clean flushbyasid decodeassists pausefilter pfthreshold avic v_vmsave_vmload vgif v_spec_ctrl umip rdpid overflow_recov succor smca sev sev_es
bugs		: sysret_ss_attrs spectre_v1 spectre_v2 spec_store_bypass retbleed smt_rsb
bogomips	: $FAKE_BOGOMIPS
TLB size	: 3072 4K pages
clflush size	: 64
cache_alignment	: 64
address sizes	: 43 bits physical, 48 bits virtual
power management: ts ttp tm hwpstate cpb eff_freq_ro [13] [14]

EOF
  done
} > "$FAKE_CPUINFO"

echo "[CPU-FAKER] Generated fake cpuinfo with $REAL_CORES cores"
echo "[CPU-FAKER] Fake CPU: $FAKE_MODEL"
