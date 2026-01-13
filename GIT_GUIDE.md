# Git Guide for This Project

## Current Status
- ✅ Git repository initialized
- ✅ Initial commit created (commit: bb569de)
- ⏳ Remote repository: **Not configured yet**

## Setting Up Remote Repository

### Step 1: Create GitHub Repository
1. Go to https://github.com/new
2. Name: `canchat1` (or your choice)
3. Choose Public/Private
4. **Don't** initialize with README
5. Click "Create repository"
6. Copy the repository URL

### Step 2: Connect Remote (Run after you have the URL)
```bash
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git branch -M main  # Rename master to main (if needed)
git push -u origin main  # Push and set upstream
```

## Common Git Operations

### Viewing Changes
```bash
git status                    # See what files changed
git log --oneline            # See commit history
git diff                     # See unstaged changes
git diff --staged            # See staged changes
```

### Making Changes
```bash
git add .                    # Stage all changes
git add <file>               # Stage specific file
git commit -m "message"      # Commit changes
git push                     # Push to remote
```

### Reverting Changes from Remote

#### 1. Get latest changes without merging
```bash
git fetch origin
```

#### 2. See what changed
```bash
git log HEAD..origin/main    # See commits on remote
git diff origin/main         # See differences
```

#### 3. Pull latest changes (merge)
```bash
git pull origin main
```

#### 4. Reset to match remote exactly (⚠️ WARNING: Discards local changes)
```bash
git fetch origin
git reset --hard origin/main
```

#### 5. Revert a specific commit
```bash
git revert <commit-hash>     # Creates new commit that undoes changes
```

#### 6. Undo local changes (before commit)
```bash
git restore <file>           # Restore specific file
git restore .                # Restore all files
```

#### 7. Undo last commit (keep changes)
```bash
git reset --soft HEAD~1
```

#### 8. Undo last commit (discard changes)
```bash
git reset --hard HEAD~1
```

### Branching
```bash
git branch                   # List branches
git branch <name>            # Create branch
git checkout <name>          # Switch branch
git checkout -b <name>       # Create and switch
git merge <branch>           # Merge branch
```

### Checking Remote Status
```bash
git remote -v                # Show remote URLs
git fetch origin             # Download changes
git status                   # Check if behind/ahead
```

## Important Notes

⚠️ **Before resetting to remote:**
- Make sure you've committed or stashed local changes you want to keep
- `git reset --hard` permanently discards uncommitted changes
- Always check `git status` first

💡 **Best Practices:**
- Commit frequently with clear messages
- Pull before pushing to avoid conflicts
- Use branches for new features
- Review changes with `git diff` before committing

## Current Branch
- Branch: `master`
- Latest commit: `bb569de` - "Initial commit: Stamp Auction Chatbot project with web scraping and RAG capabilities"
