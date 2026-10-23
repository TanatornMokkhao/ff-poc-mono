#!/usr/bin/env bash
# Deploys the one version deploy/<stage>/versions.yaml names: be first, then fe, both from the same
# commit of this repo.
#   scripts/deploy.sh staging|prod
# be: which keys it needs is apps/be/.env.example at the release tag ("# secret" marks a secret).
#     Values live in Parameter Store under /ff-poc-mono/<stage>/be/. This script runs as the deploy
#     role, which can list names but never read a value; it checks every key is there (secrets as
#     SecureString) before anything deploys. The server reads the values itself at boot, as the
#     runtime role, whose short-lived credentials come in RUNTIME_*.
# fe: the release carries one web build per stage with its config.json already baked in; this adds
#     the version, then copies it to the stage's S3 bucket (WEB_BUCKET) behind CloudFront.
set -euo pipefail

STAGE="$1"
FILE="deploy/$STAGE/versions.yaml"
SSM_PATH="/ff-poc-mono/$STAGE/be/"

get() { sed -n "s/^$1:[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$FILE"; }
# The commit the version was released from (the "# abc1234" after it).
pin() { sed -n "s/^$1:[^#]*#[[:space:]]*\([0-9a-f]*\).*/\1/p" "$FILE"; }
# Fails unless a commit the build reports for itself is the recorded one.
same_commit() {
  local what=$1 got=$2 want=$3
  if [ -z "$got" ] || [ "$got" = unknown ] || [ "$got" = "<no value>" ]; then
    echo "::error::$what does not say which commit it holds."; exit 1
  elif [ -z "$want" ]; then
    echo "::error::$FILE has no commit to compare $what with."; exit 1
  elif [[ "$got" != "$want"* ]]; then
    echo "::error::$what holds commit ${got::7}, but $FILE records ${want::7}."; exit 1
  else
    echo "Check: $what holds the recorded commit ${want::7}"
  fi
}
lines() { grep -Ev '^[[:space:]]*(#|$)' || true; }
keys() { lines | sed 's/=.*//' | sort -u; }
# Markers after a key: "# secret", "# optional" or "# secret optional". An optional key may have
# no value; when it has one, a secret must still be SecureString.
SECRET='#[[:space:]]*secret([[:space:]]+optional)?[[:space:]]*$'
OPTIONAL='#[^=]*optional[[:space:]]*$'
# grep exits 1 on no match, which pipefail turns into a silent stop; no match means no keys.
secret_keys() { { grep -E "$SECRET" || true; } | keys; }
public_keys() { lines | { grep -Ev "$SECRET" || true; } | keys; }
optional_keys() { { grep -E "$OPTIONAL" || true; } | keys; }
# Runs a command as the runtime role (the server's identity) instead of the deploy role.
as_runtime() {
  AWS_ACCESS_KEY_ID="$RUNTIME_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$RUNTIME_SECRET_ACCESS_KEY" \
    AWS_SESSION_TOKEN="$RUNTIME_SESSION_TOKEN" "$@"
}

V=$(get version)
SHA=$(pin version)
TAG="$STAGE/v$V"
echo "Deploying $STAGE: $V (${SHA:-?})"
if [ "$V" = none ]; then echo "Nothing released to $STAGE yet."; exit 0; fi
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "::error::There is no tag $TAG."; exit 1; }
[[ "$(git rev-parse "$TAG^{commit}")" == "$SHA"* ]] || { echo "::error::$TAG is not on the recorded commit $SHA."; exit 1; }
PROBLEMS=()

# be: every key in .env.example at the release must be in Parameter Store.
BE_EXAMPLE=$(git show "$TAG:apps/be/.env.example")
# "<KEY> <Type>" for every parameter under the path: names and types only, never values.
STORE=$(aws ssm describe-parameters --parameter-filters "Key=Path,Values=${SSM_PATH%/}" \
  --query 'Parameters[].[Name,Type]' --output text | awk '{n=$1; sub(".*/", "", n); print n, $2}')
type_of() { awk -v k="$1" '$1 == k {print $2}' <<<"$STORE"; }
OPT=$(optional_keys <<<"$BE_EXAMPLE")
optional() { grep -qx "$1" <<<"$OPT"; }
for k in $(public_keys <<<"$BE_EXAMPLE"); do
  [ -n "$(type_of "$k")" ] || optional "$k" || PROBLEMS+=("be: $k has no value at $SSM_PATH$k")
done
for k in $(secret_keys <<<"$BE_EXAMPLE"); do
  case "$(type_of "$k")" in
    SecureString) ;;
    "") optional "$k" || PROBLEMS+=("be: secret $k has no value at $SSM_PATH$k") ;;
    *) PROBLEMS+=("be: secret $k is stored as $(type_of "$k") at $SSM_PATH$k; it must be SecureString") ;;
  esac
done
EXTRA=$(comm -13 <(keys <<<"$BE_EXAMPLE") <(awk '{print $1}' <<<"$STORE" | sort -u) | paste -sd, -)
[ -z "$EXTRA" ] || echo "::warning::$SSM_PATH has keys be $V does not read: $EXTRA"
echo "be $V needs public: $(public_keys <<<"$BE_EXAMPLE" | paste -sd, -)"
echo "be $V needs secret: $(secret_keys <<<"$BE_EXAMPLE" | paste -sd, -)"
[ -z "$OPT" ] || echo "be $V optional (may be empty): $(paste -sd, <<<"$OPT")"

if [ ${#PROBLEMS[@]} -gt 0 ]; then
  printf '::error::%s\n' "${PROBLEMS[@]}"
  echo "Nothing was deployed."
  exit 1
fi

# The deploy role must not be able to read a value, and this stage's server must not be able to
# read the other stage's values. Either one working is a broken setup, so it stops here.
OTHER=$([ "$STAGE" = prod ] && echo staging || echo prod)
if aws ssm get-parameters-by-path --path "$SSM_PATH" --with-decryption --query 'length(Parameters)' >/dev/null 2>&1; then
  echo "::error::The deploy role can read values under $SSM_PATH; it must only list names."; exit 1
fi
echo "Check: the deploy role cannot read values under $SSM_PATH (denied)"
if as_runtime aws ssm get-parameters-by-path --path "/ff-poc-mono/$OTHER/be/" --query 'length(Parameters)' >/dev/null 2>&1; then
  echo "::error::The $STAGE runtime role can read /ff-poc-mono/$OTHER/be/."; exit 1
fi
echo "Check: the $STAGE server cannot read /ff-poc-mono/$OTHER/be/ (denied)"

IMAGE="$ECR_REPOSITORY_URL:$V"
docker pull -q "$IMAGE"
same_commit "image $IMAGE" "$(docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$IMAGE")" "$SHA"
ENVFILE=$(mktemp)
chmod 600 "$ENVFILE"
printf '%s\n' "AWS_ACCESS_KEY_ID=$RUNTIME_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY=$RUNTIME_SECRET_ACCESS_KEY" \
  "AWS_SESSION_TOKEN=$RUNTIME_SESSION_TOKEN" "AWS_REGION=$AWS_REGION" "SSM_PATH=$SSM_PATH" > "$ENVFILE"
# Migrate from the image being deployed, while the old code still runs (expand / contract keeps
# the old code working on the new schema). A failure stops here: the new code never starts.
if docker run --rm --entrypoint test "$IMAGE" -f migrate.js; then
  if ! docker run --rm --env-file "$ENVFILE" "$IMAGE" node migrate.js; then
    rm -f "$ENVFILE"
    echo "::error::be $V: migrate failed; deploy stopped, the running be is unchanged."; exit 1
  fi
else
  echo "be $V has no migrate.js: nothing to migrate."
fi
docker rm -f "be-$STAGE" >/dev/null 2>&1 || true
docker run -d --name "be-$STAGE" -p 3000:3000 --env-file "$ENVFILE" -e APP_VERSION="$V" "$IMAGE" >/dev/null
rm -f "$ENVFILE"
for _ in $(seq 1 30); do curl -fs localhost:3000/health >/dev/null && break; sleep 1; done
if ! curl -fs localhost:3000/health >/dev/null; then
  echo "::error::be $V did not start. Its log:"; docker logs "be-$STAGE" 2>&1 | tail -20; exit 1
fi
docker logs "be-$STAGE" 2>&1 | head -3
VER=$(curl -fs localhost:3000/version)
[ "$(jq -r .version <<<"$VER")" = "$V" ] || { echo "be answered version $(jq -r .version <<<"$VER"), expected $V"; exit 1; }
same_commit "the running be (/version)" "$(jq -r '.commit // empty' <<<"$VER")" "$SHA"
INFO=$(curl -fs localhost:3000/info)
echo "be /info: $INFO"
[ "$(jq -r .env <<<"$INFO")" = "$STAGE" ] || { echo "be runs with APP_ENV=$(jq -r .env <<<"$INFO"), expected $STAGE"; exit 1; }
echo "be $V is healthy with the $STAGE settings"

# fe: the web build for this stage from the release, with the version added to its config.json.
WORK=$(mktemp -d)
SITE="$WORK/site"
mkdir -p "$SITE"
gh release download "$TAG" -p "web-build-$STAGE.zip" -D "$WORK"
unzip -q "$WORK/web-build-$STAGE.zip" -d "$SITE"
CONF="$SITE/config.json"
[ -f "$CONF" ] || { echo "::error::web-build-$STAGE.zip of $V has no config.json"; exit 1; }
[ "$(jq -r .stage "$SITE/build-info.json")" = "$STAGE" ] || { echo "::error::web-build-$STAGE.zip was built for $(jq -r .stage "$SITE/build-info.json"), not $STAGE."; exit 1; }
same_commit "web-build-$STAGE.zip" "$(jq -r .commit "$SITE/build-info.json")" "$SHA"
jq --arg v "$V" '. + {versions: {be: $v, fe: $v}}' "$CONF" > "$CONF.new" && mv "$CONF.new" "$CONF"

# Hashed assets can be cached for good; the files that say what this build is must be fresh.
FRESH=(index.html config.json build-info.json)
aws s3 sync "$SITE/" "s3://$WEB_BUCKET/" --delete --only-show-errors \
  "${FRESH[@]/#/--exclude=}" --cache-control "public, max-age=31536000, immutable"
for f in "${FRESH[@]}"; do
  aws s3 cp "$SITE/$f" "s3://$WEB_BUCKET/$f" --only-show-errors --cache-control "no-store"
done
aws cloudfront create-invalidation --distribution-id "$CF_DISTRIBUTION_ID" \
  --paths "${FRESH[@]/#//}" --query Invalidation.Id --output text >/dev/null
echo "fe $V uploaded to s3://$WEB_BUCKET and CloudFront refreshed: ${WEB_URL:-}"
