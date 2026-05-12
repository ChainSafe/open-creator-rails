#!/bin/bash

version=$1
notes=$2

if [ "$(git branch --show-current)" != "main" ]; then
  git checkout main
fi

git pull

rm -rf deployments/* \
&& ./scripts/seed.sh .env

git add deployments/

git commit -m "Release $version"
git push origin main

gh release create "$version" \
  --title "$version" \
  --notes "$notes" \
  deployments/*