# ── bwrap_gui_setup ─────────────────────────────────────────

section "bwrap_gui_setup"

P=()
bwrap_gui_setup P no
[[ ${#P[@]} -gt 0 ]]         && ok "produces non-empty array"       || fail "empty array"
[[ "${P[0]}" == "--clearenv" ]] && ok "default gui setup clears env" || fail "default gui setup did not clear env"
has_pair P "--ro-bind" "/usr" && ok "includes base --ro-bind /usr"   || fail "base --ro-bind /usr missing"
has_pair P "--tmpfs" "$HOME"  && ok "includes home tmpfs"            || fail "home tmpfs missing"
has_pair P "--tmpfs" "/dev/shm" && ok "default gui setup uses private shm" || fail "default gui setup shm missing"

SETUP_NO_CLEAR=()
bwrap_gui_setup SETUP_NO_CLEAR no no tmpfs no
has_arg SETUP_NO_CLEAR "--clearenv" && fail "gui clearenv=no still adds --clearenv" || ok "gui clearenv=no omits --clearenv"

SETUP_CLEAR_INVALID=()
SETUP_CLEAR_INVALID_ERR="${TMPDIR_TEST}/setup-clearenv-invalid.err"
bwrap_gui_setup SETUP_CLEAR_INVALID no no tmpfs invalid 2>"$SETUP_CLEAR_INVALID_ERR"
SETUP_CLEAR_INVALID_RC=$?
SETUP_CLEAR_INVALID_MSG="bwrap_gui_setup: invalid clearenv mode 'invalid' (expected yes or no)"
if [[ $SETUP_CLEAR_INVALID_RC -eq 2 ]] && grep -qxF "$SETUP_CLEAR_INVALID_MSG" "$SETUP_CLEAR_INVALID_ERR"; then
    ok "gui setup rejects invalid clearenv mode with its own message"
else
    fail "invalid bwrap_gui_setup clearenv mode (rc=$SETUP_CLEAR_INVALID_RC, stderr=$(cat "$SETUP_CLEAR_INVALID_ERR" 2>/dev/null))"
fi

SETUP_SHM_BIND=()
bwrap_gui_setup SETUP_SHM_BIND no no bind
has_sequence SETUP_SHM_BIND "--bind" "/dev/shm" "/dev/shm" && ok "gui setup forwards exact shm=bind sequence" || fail "gui setup did not forward shm=bind"
has_pair SETUP_SHM_BIND "--tmpfs" "/dev/shm" && fail "gui setup shm=bind added tmpfs" || ok "gui setup shm=bind omits tmpfs"

SETUP_SHM_INVALID=()
SETUP_SHM_INVALID_ERR="${TMPDIR_TEST}/setup-shm-invalid.err"
bwrap_gui_setup SETUP_SHM_INVALID no no invalid 2>"$SETUP_SHM_INVALID_ERR"
SETUP_SHM_INVALID_RC=$?
SETUP_SHM_INVALID_MSG="bwrap_gui_setup: invalid shm mode 'invalid' (expected tmpfs or bind)"
if [[ $SETUP_SHM_INVALID_RC -eq 2 ]] && grep -qxF "$SETUP_SHM_INVALID_MSG" "$SETUP_SHM_INVALID_ERR"; then
    ok "gui setup rejects invalid shm mode with its own message"
else
    fail "invalid bwrap_gui_setup shm mode (rc=$SETUP_SHM_INVALID_RC, stderr=$(cat "$SETUP_SHM_INVALID_ERR" 2>/dev/null))"
fi

Q=()
bwrap_gui_setup Q yes
ok "bwrap_gui_setup with x11=yes runs without error"

# ── bwrap_gui_setup (gpu toggle) ─────────────────────────────

section "bwrap_gui_setup (gpu toggle)"

EXPECT_GPU_YES=()
bwrap_base EXPECT_GPU_YES
bwrap_lib64 EXPECT_GPU_YES
bwrap_gpu EXPECT_GPU_YES
bwrap_runtime_dir EXPECT_GPU_YES
bwrap_home_tmpfs EXPECT_GPU_YES

EXPECT_GPU_NO=()
bwrap_base EXPECT_GPU_NO
bwrap_lib64 EXPECT_GPU_NO
bwrap_runtime_dir EXPECT_GPU_NO
bwrap_home_tmpfs EXPECT_GPU_NO

SETUP_GPU_YES=()
bwrap_gui_setup SETUP_GPU_YES no yes
SETUP_GPU_NO=()
bwrap_gui_setup SETUP_GPU_NO no no
SETUP_GPU_DEFAULT=()
bwrap_gui_setup SETUP_GPU_DEFAULT no

if arrays_equal SETUP_GPU_DEFAULT SETUP_GPU_NO; then
    ok "default gpu argument matches gpu=no"
else
    fail "default gpu argument differs from gpu=no"
fi

if arrays_equal SETUP_GPU_YES EXPECT_GPU_YES; then
    ok "gpu=yes emits base+lib64+gpu+runtime_dir+home_tmpfs"
else
    fail "gpu=yes output differs from expected composition"
fi

if arrays_equal SETUP_GPU_NO EXPECT_GPU_NO; then
    ok "gpu=no emits base+lib64+runtime_dir+home_tmpfs without GPU resources"
else
    fail "gpu=no leaks GPU resources"
fi

# ── bwrap_gui_setup (net/gpu independence) ───────────────────

section "bwrap_gui_setup (net/gpu independence)"

RESOLV_REF=()
bwrap_resolv RESOLV_REF

EXPECT_NET_YES=()
bwrap_base EXPECT_NET_YES
bwrap_lib64 EXPECT_NET_YES
bwrap_resolv EXPECT_NET_YES
bwrap_runtime_dir EXPECT_NET_YES
bwrap_home_tmpfs EXPECT_NET_YES

EXPECT_NET_NO=()
bwrap_base EXPECT_NET_NO
bwrap_lib64 EXPECT_NET_NO
bwrap_runtime_dir EXPECT_NET_NO
bwrap_home_tmpfs EXPECT_NET_NO

EXPECT_NET_GPU_YES=()
bwrap_base EXPECT_NET_GPU_YES
bwrap_lib64 EXPECT_NET_GPU_YES
bwrap_gpu EXPECT_NET_GPU_YES
bwrap_resolv EXPECT_NET_GPU_YES
bwrap_runtime_dir EXPECT_NET_GPU_YES
bwrap_home_tmpfs EXPECT_NET_GPU_YES

SETUP_NET_YES=()
bwrap_gui_setup SETUP_NET_YES yes no
SETUP_NET_NO=()
bwrap_gui_setup SETUP_NET_NO no no
SETUP_NET_GPU_YES=()
bwrap_gui_setup SETUP_NET_GPU_YES yes yes

if arrays_equal SETUP_NET_NO EXPECT_NET_NO; then
    ok "net=no emits base+lib64+runtime_dir+home_tmpfs without resolv"
else
    fail "net=no output differs from expected composition"
fi

if [[ ${#RESOLV_REF[@]} -ge 2 ]]; then
    if arrays_equal SETUP_NET_YES EXPECT_NET_YES; then
        ok "net=yes emits base+lib64+resolv+runtime_dir+home_tmpfs"
    else
        fail "net=yes output differs from expected composition"
    fi
    if arrays_equal SETUP_NET_GPU_YES EXPECT_NET_GPU_YES; then
        ok "net=yes gpu=yes emits base+lib64+gpu+resolv+runtime_dir+home_tmpfs"
    else
        fail "net=yes gpu=yes output differs from expected composition"
    fi
else
    skip "resolv assertion (/etc/resolv.conf is not a symlink)"
    skip "net=yes gpu=yes resolv assertion (/etc/resolv.conf is not a symlink)"
fi

# ── bwrap_gui_finish ────────────────────────────────────────

section "bwrap_gui_finish"

R=()
bwrap_gui_finish R wayland no no unfiltered
[[ ${#R[@]} -gt 0 ]]      && ok "produces non-empty array"   || fail "empty array"
has_arg R "--unshare-all"  && ok "--unshare-all present"      || fail "--unshare-all missing"

CLEAR_GUI=()
bwrap_base CLEAR_GUI
bwrap_gui_finish CLEAR_GUI wayland no no unfiltered no none
[[ "${CLEAR_GUI[0]}" == "--clearenv" ]] && ok "--clearenv survives gui_finish prepend" || fail "--clearenv is not first after gui_finish"
has_pair CLEAR_GUI "--setenv" "HOME" && ok "explicit HOME survives --clearenv" || fail "HOME setenv missing after --clearenv"

S=()
bwrap_gui_finish S wayland no no none
if [[ -f /usr/lib/libhardened_malloc.so.empty ]]; then
    has_triple S "--ro-bind" "/usr/lib/libhardened_malloc.so.empty" "/usr/lib/libhardened_malloc.so" \
        && ok "malloc=no masks hardened_malloc with stub" || fail "malloc=no stub bind missing"
else
    skip "malloc=no stub bind (libhardened_malloc.so.empty not installed)"
fi

# ── bwrap_hardened_malloc ──────────────────────────────────

section "bwrap_hardened_malloc"

HM_DEFAULT=()
HM_DEFAULT_ERR="${TMPDIR_TEST}/hardened-malloc-default.err"
bwrap_hardened_malloc HM_DEFAULT 2>"$HM_DEFAULT_ERR"
HM_DEFAULT_RC=$?
if [[ -f /usr/lib/libhardened_malloc.so ]]; then
    [[ $HM_DEFAULT_RC -eq 0 ]] && ok "omitted variant defaults to default" || fail "omitted variant returned $HM_DEFAULT_RC"
    has_sequence HM_DEFAULT "--setenv" "LD_PRELOAD" "/usr/lib/libhardened_malloc.so" \
        && ok "omitted variant uses the default library" || fail "omitted variant missing default LD_PRELOAD"
else
    [[ $HM_DEFAULT_RC -eq 1 ]] && ok "missing omitted variant fails" || fail "missing omitted variant returned $HM_DEFAULT_RC"
    grep -qF "hardened_malloc library not found" "$HM_DEFAULT_ERR" \
        && ok "missing omitted variant reports the default library" || fail "missing omitted variant error is unclear"
fi

HM_LIGHT=()
HM_LIGHT_ERR="${TMPDIR_TEST}/hardened-malloc-light.err"
bwrap_hardened_malloc HM_LIGHT light 2>"$HM_LIGHT_ERR"
HM_LIGHT_RC=$?
if [[ -f /usr/lib/libhardened_malloc-light.so ]]; then
    [[ $HM_LIGHT_RC -eq 0 ]] && ok "light variant succeeds" || fail "light variant returned $HM_LIGHT_RC"
    has_sequence HM_LIGHT "--setenv" "LD_PRELOAD" "/usr/lib/libhardened_malloc-light.so" \
        && ok "light variant sets LD_PRELOAD" || fail "light variant missing LD_PRELOAD"
else
    [[ $HM_LIGHT_RC -eq 1 ]] && ok "missing light variant fails" || fail "missing light variant returned $HM_LIGHT_RC"
    grep -qF "hardened_malloc library not found" "$HM_LIGHT_ERR" \
        && ok "missing light variant reports the library" || fail "missing light variant error is unclear"
fi

HMG=()
HMG_ERR="${TMPDIR_TEST}/gui-finish-hardened-malloc.err"
bwrap_gui_finish HMG wayland no default unfiltered no none 2>"$HMG_ERR"
HMG_RC=$?
if [[ -f /usr/lib/libhardened_malloc.so ]]; then
    [[ $HMG_RC -eq 0 ]] && ok "gui_finish default enables hardened_malloc" || fail "gui_finish default returned $HMG_RC"
    has_sequence HMG "--setenv" "LD_PRELOAD" "/usr/lib/libhardened_malloc.so" \
        && ok "gui_finish default sets LD_PRELOAD" || fail "gui_finish default missing LD_PRELOAD"
else
    [[ $HMG_RC -eq 1 ]] && ok "gui_finish default fails when hardened_malloc is missing" || fail "gui_finish default returned $HMG_RC"
    grep -qF "hardened_malloc library not found" "$HMG_ERR" \
        && ok "gui_finish default reports the missing library" || fail "gui_finish default error is unclear"
fi

# ── bwrap_gui_finish (seccomp) ──────────────────────────────

section "bwrap_gui_finish (seccomp)"

SN=()
bwrap_gui_finish SN wayland no no unfiltered no default
SN_RC=$?
[[ $SN_RC -eq 0 ]] && ok "seccomp=default returns 0" || fail "seccomp=default returned $SN_RC"
has_arg SN "--seccomp" && ok "seccomp=default appends --seccomp" || fail "seccomp=default missing --seccomp"

SO=()
bwrap_gui_finish SO wayland no no unfiltered no none
SO_RC=$?
[[ $SO_RC -eq 0 ]] && ok "seccomp=none returns 0" || fail "seccomp=none returned $SO_RC"
has_arg SO "--seccomp" && fail "seccomp=none appended --seccomp" || ok "seccomp=none appends nothing"

SP=()
bwrap_gui_finish SP wayland no no unfiltered no "openat" 2>/dev/null
SP_RC=$?
[[ $SP_RC -eq 1 ]] && ok "allowlist via gui_finish is rejected" || fail "allowlist via gui_finish returned $SP_RC"
has_arg SP "--seccomp" && fail "rejected allowlist appended --seccomp" || ok "rejected allowlist appends nothing"

SNM=()
BWRAP_SECCOMP_DIR="${TMPDIR_TEST}/missing" bwrap_gui_finish SNM wayland no no unfiltered no default 2>/dev/null
SNM_RC=$?
[[ $SNM_RC -eq 1 ]] && ok "seccomp=default fails when the config is missing" || fail "missing seccomp config returned $SNM_RC"
has_arg SNM "--seccomp" && fail "failed seccomp setup appended --seccomp" || ok "failed seccomp setup appends nothing"

SOM=()
BWRAP_SECCOMP_DIR="${TMPDIR_TEST}/missing" bwrap_gui_finish SOM wayland no no unfiltered no none 2>/dev/null
SOM_RC=$?
[[ $SOM_RC -eq 0 ]] && ok "seccomp=none ignores a missing config" || fail "seccomp=none returned $SOM_RC"
has_arg SOM "--seccomp" && fail "seccomp=none appended --seccomp" || ok "seccomp=none appends nothing when the config is missing"

