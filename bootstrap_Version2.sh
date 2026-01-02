#!/usr/bin/env bash
set -euo pipefail

OWNER="kamirhosein1390-netizen"
REPO="iran-market"
BRANCH="main"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required. Install: https://cli.github.com/"
  exit 1
fi

# Change to project root
if [ -d "iran-market" ]; then
  cd iran-market
else
  echo "Directory iran-market not found. Run create_project.sh first."
  exit 1
fi

git init || true
git checkout -b "$BRANCH" || true
git add .
git commit -m "Initial commit — iran-market MVP" || echo "Nothing to commit."

# Create GitHub repo and push
if ! gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  gh repo create "$OWNER/$REPO" --public --license mit --source=. --remote=origin --push
else
  echo "Repository $OWNER/$REPO already exists. Setting remote and pushing."
  git remote remove origin 2>/dev/null || true
  git remote add origin "https://github.com/$OWNER/$REPO.git"
  git branch -M "$BRANCH"
  git push -u origin "$BRANCH"
fi

echo "✅ Repo created/pushed: https://github.com/$OWNER/$REPO"
echo ""
echo "NEXT: 1) Create server/.env (do NOT commit). 2) Deploy backend (Railway/Render/VPS). 3) Deploy frontend on Vercel and set VITE_API_URL to your backend's /api URL."