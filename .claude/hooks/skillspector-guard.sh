#!/usr/bin/env bash
# skillspector-guard.sh
# Hook PreToolUse (matcher "Bash") de Claude Code.
# Escanea con NVIDIA SkillSpector (--no-llm) el repo de GitHub que un comando
# esta a punto de traer a tu equipo, y decide segun el score/severidad del JSON.
#
#   LOW       -> pasa en silencio
#   MEDIUM    -> pasa con aviso corto de hallazgos
#   HIGH/CRIT -> permissionDecision "ask" con score y 3 hallazgos mas graves
#   falla o timeout -> pasa, pero avisa que el repo NO se reviso
#
# Compatible con bash 3.2 (macOS). Requiere: jq, skillspector.

set -u
export PATH="$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Presupuesto total de escaneo en segundos (el hook tiene timeout de 120 s).
BUDGET="${SKILLSPECTOR_GUARD_BUDGET:-100}"
MAX_REPOS=3

input="$(cat)"

# ---------- Prefiltro barato: casi todos los comandos terminan aqui ----------
case "$input" in
  *clone*|*skills*|*mcp*|*install*|*curl*|*wget*) ;;
  *) exit 0 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"systemMessage":"SkillSpector guard: falta jq, el comando NO se reviso."}'
  exit 0
fi

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# ---------- 0) Quitar texto que no se ejecuta ----------
# Evita falsos positivos con mensajes de commit, echo, grep y heredocs que solo
# MENCIONAN "git clone" & co. Conserva lo que si se ejecuta: el contenido de
# bash -c / sh -c / eval, los $(...) y `...` dentro de comillas, y los heredocs
# que alimentan a un interprete (| bash, python, etc.). Ante duda (comilla sin
# cerrar, heredoc sin terminador) deja el texto tal cual: peor caso, un aviso de mas.
# Solo se usa para DETECTAR el comando; los links se sacan del comando original.
read -r -d '' STRIP_AWK <<'AWKEOF' || true
function isexec(t) { return (t ~ /(^|[ \t\n;&|(])(-[A-Za-z]*c|eval)[ \t]*$/) }
function strip_text(str,   sS, sP, sN, r) {
  sS = S; sP = P; sN = N
  S = str; P = 1; N = length(str)
  r = parse(0)
  S = sS; P = sP; N = sN
  return r
}
function find_term(pos, delim, dash,   le, line) {
  while (pos <= N) {
    le = index(substr(S, pos), "\n")
    line = (le > 0) ? substr(S, pos, le - 1) : substr(S, pos)
    if (dash) sub(/^\t+/, "", line)
    if (line == delim) return pos
    if (le == 0) return 0
    pos += le
  }
  return 0
}
function parse(sub_mode,   out, c, d, depth, j, k, q, w, ch, seg, content, inner, startp, closed, hd, hd_delim, hd_dash, endp, lastline, body) {
  out = ""; depth = 0; hd = 0
  while (P <= N) {
    c = substr(S, P, 1)
    if (c == "\\") { out = out substr(S, P, 2); P += 2; continue }
    if (c == "'") {
      if (substr(out, length(out), 1) == "$") {
        # $'...' (ANSI-C): \' no cierra la cadena
        k = P + 1
        while (k <= N) {
          ch = substr(S, k, 1)
          if (ch == "\\") { k += 2; continue }
          if (ch == "'") break
          k++
        }
        j = k - P
        if (k > N) j = 0
      } else {
        j = index(substr(S, P + 1), "'")
      }
      if (j == 0) { out = out substr(S, P); P = N + 1; break }
      content = substr(S, P + 1, j - 1)
      if (isexec(out)) out = out "'" strip_text(content) "'"
      else if (content ~ /^git\+/) out = out "'" content "'"
      else out = out "''"
      P += j + 1; continue
    }
    if (c == "\"") {
      if (isexec(out)) {
        k = P + 1
        while (k <= N) {
          ch = substr(S, k, 1)
          if (ch == "\\") { k += 2; continue }
          if (ch == "\"") break
          k++
        }
        content = substr(S, P + 1, k - P - 1)
        out = out "\"" strip_text(content) "\""
        P = k + 1; continue
      }
      startp = P; P++; seg = ""; closed = 0
      while (P <= N) {
        ch = substr(S, P, 1)
        if (ch == "\\") { P += 2; continue }
        if (ch == "\"") { P++; closed = 1; break }
        if (ch == "$" && substr(S, P + 1, 1) == "(") {
          P += 2
          inner = parse(1)
          seg = seg " $(" inner ") "
          continue
        }
        if (ch == "`") {
          k = index(substr(S, P + 1), "`")
          if (k == 0) { break }
          seg = seg " `" strip_text(substr(S, P + 1, k - 1)) "` "
          P += k + 1; continue
        }
        P++
      }
      if (!closed) { out = out substr(S, startp); P = N + 1; break }
      content = substr(S, startp + 1, P - startp - 2)
      if (content ~ /^git\+/) seg = seg " " content
      out = out "\"" seg "\""
      continue
    }
    if (c == "#") {
      d = (out == "") ? "\n" : substr(out, length(out), 1)
      if (d == " " || d == "\t" || d == "\n" || d == ";") {
        while (P <= N && substr(S, P, 1) != "\n") P++
        continue
      }
    }
    if (c == "(") { depth++; out = out c; P++; continue }
    if (c == ")") {
      if (sub_mode && depth == 0) { P++; return out }
      if (depth > 0) depth--
      out = out c; P++; continue
    }
    if (c == "<" && substr(S, P, 2) == "<<" && substr(S, P + 2, 1) != "<") {
      q = P + 2; hd_dash = 0
      if (substr(S, q, 1) == "-") { hd_dash = 1; q++ }
      while (substr(S, q, 1) == " " || substr(S, q, 1) == "\t") q++
      w = ""
      while (q <= N) {
        ch = substr(S, q, 1)
        if (ch ~ /[A-Za-z0-9_'"\\]/) { w = w ch; q++ } else break
      }
      gsub(/['"\\]/, "", w)
      if (w ~ /^[A-Za-z_][A-Za-z0-9_]*$/) {
        hd = 1; hd_delim = w
        out = out substr(S, P, q - P); P = q
        continue
      }
    }
    if (c == "\n") {
      out = out c; P++
      if (hd) {
        hd = 0
        endp = find_term(P, hd_delim, hd_dash)
        if (endp > 0) {
          lastline = out; sub(/\n$/, "", lastline); sub(/^.*\n/, "", lastline)
          if (lastline ~ INTERP) {
            body = substr(S, P, endp - P)
            out = out strip_text(body)
          }
          P = endp
        }
      }
      continue
    }
    out = out c; P++
  }
  return out
}
BEGIN {
  INTERP = "(^|[^A-Za-z0-9_./-])(ba|z|da|k)?sh([ \t;&|<>)]|$)|(^|[^A-Za-z0-9_./-])(eval|source|python[0-9.]*|node|ruby|perl|php)([ \t;&|<>)]|$)"
}
{ buf = buf $0 "\n" }
END { S = buf; P = 1; N = length(S); printf "%s", parse(0) }
AWKEOF

scan_cmd="$cmd"
if command -v awk >/dev/null 2>&1; then
  stripped="$(printf '%s' "$cmd" | awk "$STRIP_AWK" 2>/dev/null)" && [ -n "$stripped" ] && scan_cmd="$stripped"
fi

# ---------- 1) Es un comando que trae codigo externo? ----------
S='[[:space:]]'
B='(^|[^[:alnum:]_./-])'
guarded=0
for re in \
  "${B}git${S}+([^;&|]*${S})?clone(${S}|\$)" \
  "${B}gh${S}+repo${S}+clone" \
  "${B}npx${S}+([^;&|]*${S})?skills(@[^[:space:]]+)?${S}+add" \
  "${B}claude${S}+mcp${S}+add" \
  "${B}pip[0-9.]*${S}+([^;&|]*${S})?install[^;&|]*git\\+" \
  "${B}uv${S}+tool${S}+install[^;&|]*git\\+" \
  "${B}(curl|wget)${S}[^|;&]*\\|${S}*(sudo${S}+(-[^[:space:]]+${S}+)*)?(ba|z|da)?sh([^[:alnum:]_]|\$)" \
  "${B}(ba|z|da)?sh${S}+(-c${S}+)?[\"']?(<\\(|\\\$\\()${S}*(curl|wget)" \
  "${B}eval${S}+[\"']?\\\$\\(${S}*(curl|wget)"
do
  if printf '%s' "$scan_cmd" | grep -Eq -- "$re"; then guarded=1; break; fi
done
[ "$guarded" = 1 ] || exit 0

# ---------- 2) Sacar repos de GitHub del comando ----------
repos="$(
  {
    # URLs completas, ssh, git+https, raw.githubusercontent
    printf '%s' "$cmd" | grep -Eo \
      -e '(git\+)?(https?|ssh|git)://([^@/[:space:]]+@)?github\.com[:/][A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' \
      -e 'git@github\.com:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' \
      -e 'raw\.githubusercontent\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' \
      -e 'github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' 2>/dev/null |
      sed -E 's#^git\+##; s#^(https?|ssh|git)://([^@/]*@)?##; s#^git@##;
              s#^raw\.githubusercontent\.com/#github.com/#; s#^github\.com[:/]##'

    # Formato corto usuario/repo en gh repo clone y npx skills add
    for re in \
      "gh${S}+repo${S}+clone${S}+(-[^[:space:]]+${S}+)*[\"']?([A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+)" \
      "skills(@[^[:space:]]+)?${S}+add${S}+(-[^[:space:]]+${S}+)*[\"']?([A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+)"
    do
      rest="$cmd"
      while [[ $rest =~ $re ]]; do
        n=$(( ${#BASH_REMATCH[@]} - 1 ))
        printf '%s\n' "${BASH_REMATCH[$n]}"
        rest="${rest#*"${BASH_REMATCH[0]}"}"
      done
    done
  } | sed -E 's#\.git$##' | grep -E '^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+$' | awk '!seen[$0]++' | head -n "$MAX_REPOS"
)"

emit_notice() {   # $1 = texto para el usuario y para Claude
  jq -n --arg m "$1" '{
    systemMessage: $m,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: ("AVISO DEL GUARDIA SKILLSPECTOR (repite esto al usuario en tu respuesta): " + $m)
    }
  }'
}

if [ -z "$repos" ]; then
  emit_notice "SkillSpector guard: el comando trae codigo externo pero no encontre un link de GitHub. NO se reviso."
  exit 0
fi

# ---------- 3) Escaneo ----------
SS="${SKILLSPECTOR_BIN:-skillspector}"
if ! command -v "$SS" >/dev/null 2>&1; then
  emit_notice "SkillSpector guard: skillspector no esta instalado. NO se reviso: $(printf '%s' "$repos" | tr '\n' ' ')"
  exit 0
fi

run_timeout() {   # $1 = segundos, resto = comando. Devuelve 124 si vence.
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout -k 3 "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout -k 3 "$secs" "$@"; return $?; fi
  "$@" & local pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local wd=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$wd" 2>/dev/null
  [ "$rc" -eq 143 ] && rc=124
  return $rc
}

tmp="$(mktemp -d 2>/dev/null || mktemp -d -t skillspector-guard)"
trap 'rm -rf "$tmp"' EXIT

start=$SECONDS
ask_msgs=""; warn_msgs=""; skip_msgs=""; i=0

while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  i=$((i + 1))
  url="https://github.com/$repo"
  left=$(( BUDGET - (SECONDS - start) ))
  if [ "$left" -lt 5 ]; then
    skip_msgs="${skip_msgs}${repo}: sin tiempo restante (NO se reviso)\n"
    continue
  fi

  out="$tmp/r$i.json"
  run_timeout "$left" "$SS" scan "$url" --no-llm -f json -o "$out" >"$tmp/r$i.log" 2>&1
  rc=$?

  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    skip_msgs="${skip_msgs}${repo}: el escaneo no termino en ${left}s (NO se reviso)\n"
    continue
  fi
  # No confiar solo en el codigo de salida: exige JSON valido con score y severidad.
  if [ ! -s "$out" ] || ! jq -e '.risk_assessment.severity and (.risk_assessment.score != null)' "$out" >/dev/null 2>&1; then
    skip_msgs="${skip_msgs}${repo}: el escaneo fallo (rc=$rc), sin reporte valido (NO se reviso)\n"
    continue
  fi

  sev="$(jq -r '.risk_assessment.severity' "$out")"
  score="$(jq -r '.risk_assessment.score' "$out")"
  cov="$(jq -r '.analysis_completeness.coverage_percent // 100' "$out")"
  complete="$(jq -r '.analysis_completeness.is_complete // true' "$out")"
  nissues="$(jq -r '(.issues // []) | length' "$out")"

  top="$(jq -r '
    def rank: {"CRITICAL":4,"HIGH":3,"MEDIUM":2,"LOW":1}[.] // 0;
    (.issues // [])
    | sort_by([-(.severity | rank), -(.confidence // 0)])
    | .[0:3][]
    | "  - [\(.severity)] \(.category): \((.pattern // .finding // "")[0:140]) (\(.location.file // "?"):\(.location.start_line // "?"))"
  ' "$out")"

  partial=""
  if [ "$complete" != "true" ]; then partial=" Cobertura parcial: ${cov}% (parte del repo NO se reviso)."; fi

  case "$sev" in
    CRITICAL|HIGH)
      ask_msgs="${ask_msgs}${repo}: severidad ${sev}, score ${score}/100, ${nissues} hallazgos.${partial}\nTop 3:\n${top}\n"
      ;;
    MEDIUM)
      warn_msgs="${warn_msgs}${repo}: severidad MEDIUM, score ${score}/100, ${nissues} hallazgos.${partial}\n${top}\n"
      ;;
    *)  # LOW
      if [ -n "$partial" ]; then
        warn_msgs="${warn_msgs}${repo}: severidad LOW, score ${score}/100.${partial}\n"
      fi
      ;;
  esac
done <<EOF
$repos
EOF

# ---------- 4) Decision ----------
if [ -n "$ask_msgs" ]; then
  reason="$(printf 'SkillSpector detecto riesgo ALTO. No ejecutes sin revisar.\n'; printf '%b' "$ask_msgs")"
  [ -n "$warn_msgs" ] && reason="$reason$(printf '\nOtros avisos:\n'; printf '%b' "$warn_msgs")"
  [ -n "$skip_msgs" ] && reason="$reason$(printf '\nNO revisados:\n'; printf '%b' "$skip_msgs")"
  jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
fi

msg=""
[ -n "$skip_msgs" ] && msg="SkillSpector guard, NO REVISADO:\n${skip_msgs}"
[ -n "$warn_msgs" ] && msg="${msg}SkillSpector guard, aviso:\n${warn_msgs}"
if [ -n "$msg" ]; then
  emit_notice "$(printf '%b' "$msg")"
fi
exit 0
