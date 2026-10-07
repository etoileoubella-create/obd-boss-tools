#!/bin/bash
# Installation de la commande pplx pour iSH (iPad) - OBD-BOSS
# Usage : curl -fsSL https://raw.githubusercontent.com/etoileoubella-create/obd-boss-tools/main/install.sh | bash
set -u

echo "== Installation de pplx =="

# 1. Outils nécessaires
for outil in curl jq; do
  if ! command -v "$outil" >/dev/null 2>&1; then
    echo "-> Installation de $outil..."
    sudo apk add "$outil" >/dev/null 2>&1 || apk add "$outil" >/dev/null 2>&1 || {
      echo "Erreur : impossible d'installer $outil. Lance : sudo apk add $outil"; exit 1; }
  fi
done
echo "-> curl et jq : OK"

# 2. Dossiers
mkdir -p "$HOME/bin" "$HOME/obd-boss/pl07"
echo "-> Dossiers ~/bin et ~/obd-boss/pl07 : OK"

# 3. Script pplx
cat > "$HOME/bin/pplx" <<'EOF'
#!/bin/bash
# pplx : recherche web sourcée via l'Agent API Perplexity (/v1/responses)
set -o pipefail

Q="$*"
if [ -z "$Q" ]; then
  echo 'Usage : pplx "Ta question"'
  exit 1
fi
if [ -z "${PERPLEXITY_API_KEY:-}" ]; then
  echo "Erreur : PERPLEXITY_API_KEY est absente. Lance : source ~/.bashrc"
  exit 1
fi

TMP="$(mktemp)"
CODE=$(curl -sS --max-time 120 -o "$TMP" -w '%{http_code}' https://api.perplexity.ai/v1/responses \
  -H "Authorization: Bearer $PERPLEXITY_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg q "$Q" '{preset:"fast",input:$q}')")

if [ "$CODE" != "200" ]; then
  echo "Erreur API (HTTP $CODE) :"
  case "$CODE" in
    401) echo "Clé invalide ou révoquée. Relance l'installation avec une nouvelle clé." ;;
    429) echo "Trop de requêtes, réessaie dans une minute." ;;
  esac
  jq -r '.error.message // .' "$TMP" 2>/dev/null || cat "$TMP"
  rm -f "$TMP"
  exit 1
fi

jq -r '
  (.output[]? | select(.type == "message") | .content[]? | select(.type == "output_text") | .text),
  "",
  "Sources :",
  ([.output[]? | select(.type == "search_results") | .results[]? | .url] | unique[])
' "$TMP"
rm -f "$TMP"
EOF
chmod +x "$HOME/bin/pplx"
echo "-> Commande ~/bin/pplx : OK"

# 4. Ancienne version cassée
if [ -e /usr/local/bin/pplx ]; then
  sudo rm -f /usr/local/bin/pplx 2>/dev/null && echo "-> Ancienne version /usr/local/bin/pplx supprimée"
fi

# 5. Clé API
ANCIENNE="${PERPLEXITY_API_KEY:-}"
K="${PPLX_INSTALL_KEY:-}"
if [ -z "$K" ] && [ -r /dev/tty ]; then
  echo ""
  if [ -n "$ANCIENNE" ]; then
    echo "Une clé existe déjà. Appuie sur Entrée pour la garder, ou colle une nouvelle clé."
  fi
  printf "Clé Perplexity (rien ne s'affiche) : "
  read -rs K < /dev/tty
  echo ""
fi
[ -z "$K" ] && K="$ANCIENNE"
if [ -z "$K" ]; then
  echo "Erreur : aucune clé fournie. Relance l'installation."
  exit 1
fi

# 6. Fichiers de démarrage (sans doublons)
touch "$HOME/.bashrc"
sed -i '/PERPLEXITY_API_KEY/d;/HOME\/bin/d' "$HOME/.bashrc"
echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
printf 'export PERPLEXITY_API_KEY=%q\n' "$K" >> "$HOME/.bashrc"
chmod 600 "$HOME/.bashrc"
# iSH ouvre un shell de connexion : on s'assure que .bashrc est lu à chaque ouverture
for f in "$HOME/.bash_profile" "$HOME/.profile"; do
  touch "$f"
  grep -q 'obd-boss-pplx' "$f" || echo '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc" # obd-boss-pplx' >> "$f"
done
echo "-> Clé et PATH enregistrés : OK"

# 7. Test réel (affiche seulement le code HTTP)
CODE=$(curl -sS --max-time 60 -o /dev/null -w '%{http_code}' https://api.perplexity.ai/v1/responses \
  -H "Authorization: Bearer $K" -H "Content-Type: application/json" \
  -d '{"preset":"fast","input":"Réponds juste OK"}')
unset K ANCIENNE
case "$CODE" in
  200) echo "-> Test API : OK (HTTP 200)" ;;
  401) echo "-> Test API : clé refusée (HTTP 401). Relance l'installation avec une clé valide." ;;
  *)   echo "-> Test API : HTTP $CODE" ;;
esac

echo ""
echo "Terminé. Tape maintenant :  source ~/.bashrc"
echo 'Puis essaie :  pplx "prix pompe à eau DAF XD Paccar MX-11 neuf"'
