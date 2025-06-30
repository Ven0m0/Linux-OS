# Optimize the current Git repository
function git-opt
    echo "🧹 Expiring reflogs..."
    git reflog expire --expire=now --all
    and echo "🧼 Running aggressive GC..."
    and git gc --prune=now --aggressive
    and echo "📦 Repacking objects..."
    and git repack -a -d --depth=250 --window=250 --write-bitmap-index
    and echo "🗑️ Cleaning ignored junk..."
    and git clean -fdX
end
