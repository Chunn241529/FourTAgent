#!/bin/bash
# git.sh - Smart Git Helper Script with Auto-Complete

# ====== AUTO-COMPLETE SETUP ======
setup_autocomplete() {
    local completion_file="git-completion.bash"
    local bashrc_file="$HOME/.bashrc"
    
    if [[ "$1" == "--install-completion" ]]; then
        cat > "$completion_file" << 'EOF'
#!/bin/bash
# git-completion.bash - Auto-completion for git.sh
_git_sh_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Main commands
    opts="init commit push branch checkout merge status history revert reset tag stash diff help --install-completion"
    
    # Get available branches for checkout and merge
    local branches=""
    if command -v git &> /dev/null && git rev-parse --git-dir &> /dev/null 2>&1; then
        branches=$(git branch -a 2>/dev/null | sed 's/^* //' | sed 's/remotes\/[^/]*\///' | sort -u | tr '\n' ' ')
    fi
    
    # Auto-complete based on context
    case "${prev}" in
        ./git.sh|git.sh)
            COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
            return 0
            ;;
        checkout|merge)
            if [[ -n "$branches" ]]; then
                COMPREPLY=( $(compgen -W "${branches}" -- "${cur}") )
                return 0
            fi
            ;;
        commit|push|status|history|help|init|--install-completion)
            COMPREPLY=()
            return 0
            ;;
        revert|reset|branch)
            # For these commands, don't suggest anything specific
            COMPREPLY=()
            return 0
            ;;
    esac
    
    # Default: auto-complete main commands
    COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
}

complete -F _git_sh_completion ./git.sh
complete -F _git_sh_completion git.sh
EOF
        chmod +x "$completion_file"
        
        # Add to .bashrc if not already present
        if ! grep -q "git-completion.bash" "$bashrc_file" 2>/dev/null; then
            echo -e "\n# Auto-completion for git.sh" >> "$bashrc_file"
            echo "source $(pwd)/$completion_file" >> "$bashrc_file"
            echo -e "${GREEN}✅ Đã cài đặt auto-complete!${RESET}"
            echo -e "${CYAN}Chạy: ${YELLOW}source ~/.bashrc${CYAN} hoặc mở terminal mới để áp dụng${RESET}"
        else
            echo -e "${YELLOW}⚠️  Auto-complete đã được cài đặt trước đó${RESET}"
            echo -e "${CYAN}Chạy: ${YELLOW}source ~/.bashrc${CYAN} để áp dụng ngay${RESET}"
        fi
        exit 0
    fi
}

# Initialize autocomplete setup
setup_autocomplete "$1"

# ====== CONFIGURATION ======
set -e

REPO_NAME="4T_task"
GITHUB_USER="Chunn241529"
REMOTE="origin"
BRANCH_MAIN="main"

# ====== COLORS ======
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
RED='\033[1;31m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
RESET='\033[0m'

# ====== CONFIG ======
setup_config() {
    echo -e "${CYAN}🔧 Thiết lập Git config...${RESET}"
    
    if ! git config user.name &>/dev/null; then
        echo -e "${CYAN}👤 Nhập tên Git user:${RESET}"
        read -r user_name
        git config --global user.name "$user_name"
        echo -e "${GREEN}✅ Đã thiết lập user.name${RESET}"
    fi
    
    if ! git config user.email &>/dev/null; then
        echo -e "${CYAN}📧 Nhập email:${RESET}"
        read -r user_email
        git config --global user.email "$user_email"
        echo -e "${GREEN}✅ Đã thiết lập user.email${RESET}"
    fi
    
    git config pull.rebase false
    echo -e "${GREEN}✅ Git config hoàn tất${RESET}"
}

# ====== INIT ======
init_repo() {
    echo -e "${CYAN}🚀 Khởi tạo repository...${RESET}"
    
    if [[ ! -d ".git" ]]; then
        git init
        echo "# $REPO_NAME" > README.md
        git add README.md
        git commit -m "Initial commit"
        echo -e "${GREEN}✅ Repository đã được khởi tạo${RESET}"
    else
        echo -e "${YELLOW}⚠️  Repository đã tồn tại${RESET}"
    fi

    if ! git remote | grep -q "$REMOTE"; then
        git remote add "$REMOTE" "https://github.com/$GITHUB_USER/$REPO_NAME.git"
        echo -e "${GREEN}✅ Đã thêm remote: $REMOTE${RESET}"
    else
        echo -e "${YELLOW}⚠️  Remote '$REMOTE' đã tồn tại${RESET}"
    fi

    echo -e "${CYAN}🔄 Đồng bộ với GitHub...${RESET}"
    git pull "$REMOTE" "$BRANCH_MAIN" --allow-unrelated-histories 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Branch '$BRANCH_MAIN' chưa tồn tại trên remote, tạo mới...${RESET}"
    }
    
    git push -u "$REMOTE" "$BRANCH_MAIN"
    echo -e "${GREEN}✅ Repository đã được đồng bộ với GitHub${RESET}"
}

# ====== COMMIT ======
do_commit() {
    local msg="${1:-Auto commit $(date '+%Y-%m-%d %H:%M:%S')}"
    
    if ! git diff --quiet || ! git diff --cached --quiet; then
        git add .
        git commit -m "$msg"
        echo -e "${GREEN}✅ Đã commit: ${CYAN}$msg${RESET}"
    else
        echo -e "${YELLOW}⚠️  Không có thay đổi để commit${RESET}"
    fi
}

# ====== PUSH ======
do_push() {
    local branch
    branch=$(git branch --show-current)
    local force_flag=""
    
    # Check for force flag
    if [[ "$1" == "-f" || "$1" == "--force" ]]; then
        echo -e "${YELLOW}⚠️  CẢNH BÁO: Force push sẽ ghi đè lịch sử remote!${RESET}"
        echo -e "${CYAN}Bạn có chắc chắn? (y/N):${RESET}"
        read -r confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            force_flag="--force"
            echo -e "${RED}🚨 Đang force push...${RESET}"
        else
            echo -e "${YELLOW}⚠️  Đã hủy force push${RESET}"
            exit 0
        fi
    else
        echo -e "${CYAN}🔄 Đang đồng bộ branch '$branch'...${RESET}"
        git pull "$REMOTE" "$branch" --no-edit 2>/dev/null || {
            echo -e "${YELLOW}⚠️  Chưa có branch '$branch' trên remote, tạo mới...${RESET}"
        }
    fi
    
    git push "$REMOTE" "$branch" $force_flag
    echo -e "${GREEN}✅ Đã push branch '$branch' lên GitHub${RESET}"
}

# ====== BRANCH ======
create_branch() {
    local branch_name="${1:-feature/$(date '+%Y%m%d-%H%M%S')}"
    
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        echo -e "${YELLOW}⚠️  Branch '$branch_name' đã tồn tại, chuyển sang branch này${RESET}"
        git checkout "$branch_name"
    else
        git checkout -b "$branch_name"
        echo -e "${GREEN}✅ Đã tạo và chuyển sang branch: $branch_name${RESET}"
    fi
}

checkout_branch() {
    local branch_name="$1"
    
    if [[ -z "$branch_name" ]]; then
        echo -e "${CYAN}🌿 Các branch có sẵn:${RESET}"
        git branch -a
        echo -e "${CYAN}📝 Nhập tên branch:${RESET}"
        read -r branch_name
    fi
    
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        git checkout "$branch_name"
        echo -e "${GREEN}✅ Đã chuyển sang branch: $branch_name${RESET}"
    else
        echo -e "${RED}❌ Branch '$branch_name' không tồn tại${RESET}"
        echo -e "${CYAN}🌿 Các branch có sẵn:${RESET}"
        git branch -a
        exit 1
    fi
}

# ====== MERGE ======
do_merge() {
    local target_branch="${1:-$BRANCH_MAIN}"
    local current_branch
    current_branch=$(git branch --show-current)

    if [[ "$current_branch" == "$target_branch" ]]; then
        echo -e "${YELLOW}⚠️  Đang ở branch đích ($target_branch), không thể merge chính nó${RESET}"
        exit 0
    fi

    echo -e "${CYAN}🔄 Đang merge '$current_branch' vào '$target_branch'...${RESET}"
    
    git checkout "$target_branch"
    git pull "$REMOTE" "$target_branch" 2>/dev/null || true
    git merge "$current_branch" --no-ff -m "Merge branch '$current_branch' into '$target_branch'"
    git push "$REMOTE" "$target_branch"
    
    echo -e "${GREEN}✅ Đã merge '$current_branch' → '$target_branch' thành công${RESET}"
}

# ====== HISTORY ======
show_history() {
    echo -e "${CYAN}📜 Lịch sử commit (10 cái gần nhất):${RESET}"
    git log --oneline --graph -10 --color=always || {
        echo -e "${YELLOW}⚠️  Chưa có commit nào${RESET}"
    }
}

# ====== CLEANUP PYCACHE ======
clear_pycache() {
    echo -e "${CYAN}🧹 Đang xóa tất cả __pycache__...${RESET}"
    
    local count=$(find . -type d -name "__pycache__" 2>/dev/null | wc -l)
    
    if [[ $count -eq 0 ]]; then
        echo -e "${GREEN}✅ Không tìm thấy __pycache__ nào${RESET}"
    else
        find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
        echo -e "${GREEN}✅ Đã xóa $count thư mục __pycache__${RESET}"
    fi
}

# ====== COMMIT ======
do_commit() {
    local msg="$1"
    
    if [[ -z "$msg" ]]; then
        echo -e "${CYAN}📝 Nhập commit message:${RESET}"
        read -r msg
    fi
    
    if [[ -z "$msg" ]]; then
        echo -e "${RED}❌ Commit message không được để trống${RESET}"
        exit 1
    fi
    
    # Pull latest changes
    echo -e "${CYAN}🔄 Đang pull thay đổi mới nhất...${RESET}"
    local current_branch=$(git branch --show-current)
    git pull "$REMOTE" "$current_branch" 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Không thể pull (có thể chưa có remote hoặc branch mới)${RESET}"
    }
    
    # Clear pycache
    clear_pycache
    
    git add -A
    git commit -m "$msg"
    echo -e "${GREEN}✅ Đã commit: '$msg'${RESET}"
    echo -e "${YELLOW}💡 Chạy ${CYAN}./git.sh push${YELLOW} để đẩy lên GitHub${RESET}"
}

# ====== REVERT ======
revert_commit() {
    local commit_hash="$1"
    
    if [[ -z "$commit_hash" ]]; then
        echo -e "${CYAN}📜 Chọn commit để revert:${RESET}"
        show_history
        echo -e "${CYAN}📝 Nhập commit hash:${RESET}"
        read -r commit_hash
    fi
    
    if git show "$commit_hash" &>/dev/null; then
        git revert --no-edit "$commit_hash"
        echo -e "${GREEN}✅ Đã revert commit: $commit_hash${RESET}"
        echo -e "${YELLOW}💡 Revert tạo commit mới, chạy ${CYAN}./git.sh push${YELLOW} để áp dụng${RESET}"
    else
        echo -e "${RED}❌ Commit '$commit_hash' không tồn tại${RESET}"
        exit 1
    fi
}

# ====== RESET ======
reset_to_commit() {
    local commit_hash="$1"
    
    if [[ -z "$commit_hash" ]]; then
        echo -e "${CYAN}📜 Chọn commit để reset về:${RESET}"
        show_history
        echo -e "${CYAN}📝 Nhập commit hash:${RESET}"
        read -r commit_hash
    fi

    echo -e "${YELLOW}⚠️  CẢNH BÁO: Reset sẽ thay đổi lịch sử commit!${RESET}"
    echo -e "${CYAN}🔧 Chọn loại reset:${RESET}"
    echo -e "  ${GREEN}1. Soft${RESET}   - Giữ thay đổi trong staging area"
    echo -e "  ${GREEN}2. Mixed${RESET}  - Giữ thay đổi trong working directory (mặc định)"
    echo -e "  ${GREEN}3. Hard${RESET}   - Xóa hết thay đổi (NGUY HIỂM)"
    echo -e "  ${GREEN}4. Hủy${RESET}    - Không thực hiện reset"
    echo -e "${CYAN}Lựa chọn (1/2/3/4):${RESET}"
    read -r reset_type

    case "$reset_type" in
        1|"soft"|"Soft")
            git reset --soft "$commit_hash"
            echo -e "${GREEN}✅ Soft reset đến: $commit_hash${RESET}"
            echo -e "${YELLOW}💡 Thay đổi được giữ trong staging area${RESET}"
            ;;
        3|"hard"|"Hard")
            echo -e "${RED}🚨 HARD RESET - Tất cả thay đổi sau commit sẽ bị XÓA!${RESET}"
            echo -e "${CYAN}Bạn có chắc chắn? (y/N):${RESET}"
            read -r confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                git reset --hard "$commit_hash"
                echo -e "${GREEN}✅ Hard reset đến: $commit_hash${RESET}"
                echo -e "${RED}💡 Tất cả thay đổi sau commit đã bị xóa${RESET}"
            else
                echo -e "${YELLOW}⚠️  Đã hủy reset${RESET}"
                exit 0
            fi
            ;;
        4|"cancel"|"hủy")
            echo -e "${YELLOW}⚠️  Đã hủy reset${RESET}"
            exit 0
            ;;
        *)
            git reset --mixed "$commit_hash"
            echo -e "${GREEN}✅ Mixed reset đến: $commit_hash${RESET}"
            echo -e "${YELLOW}💡 Thay đổi được giữ trong working directory${RESET}"
            ;;
    esac
    
    echo -e "${YELLOW}📝 Chạy ${CYAN}./git.sh push -f${YELLOW} nếu cần áp dụng reset lên remote${RESET}"
}

# ====== STATUS ======
show_status() {
    echo -e "${CYAN}📂 Repository: $(basename "$(git rev-parse --show-toplevel 2>/dev/null)")${RESET}"
    echo -e "${CYAN}🌿 Branch hiện tại: $(git branch --show-current)${RESET}"
    echo -e "${CYAN}🔄 Remote: $(git remote get-url "$REMOTE" 2>/dev/null || echo "Chưa thiết lập")${RESET}"
    echo
    git status -sb || {
        echo -e "${YELLOW}⚠️  Không thể lấy trạng thái${RESET}"
    }
}

# ====== TAG ======
manage_tags() {
    local action="$1"
    local tag_name="$2"
    
    case "$action" in
        create|c)
            if [[ -z "$tag_name" ]]; then
                echo -e "${CYAN}📝 Nhập tên tag (vd: v1.0.0):${RESET}"
                read -r tag_name
            fi
            
            if [[ -z "$tag_name" ]]; then
                echo -e "${RED}❌ Tag name không được để trống${RESET}"
                exit 1
            fi
            
            git tag "$tag_name"
            echo -e "${GREEN}✅ Đã tạo tag: $tag_name${RESET}"
            echo -e "${YELLOW}💡 Chạy ${CYAN}./git.sh tag push $tag_name${YELLOW} để đẩy tag lên GitHub${RESET}"
            ;;
        push|p)
            if [[ -z "$tag_name" ]]; then
                echo -e "${CYAN}📝 Nhập tên tag để push (hoặc 'all' cho tất cả):${RESET}"
                read -r tag_name
            fi
            
            if [[ "$tag_name" == "all" ]]; then
                git push "$REMOTE" --tags
                echo -e "${GREEN}✅ Đã push tất cả tags lên GitHub${RESET}"
            else
                git push "$REMOTE" "$tag_name"
                echo -e "${GREEN}✅ Đã push tag '$tag_name' lên GitHub${RESET}"
            fi
            ;;
        list|l|"")  
            echo -e "${CYAN}🏷️  Danh sách tags:${RESET}"
            git tag -l --sort=-v:refname || {
                echo -e "${YELLOW}⚠️  Chưa có tag nào${RESET}"
            }
            ;;
        delete|d)
            if [[ -z "$tag_name" ]]; then
                echo -e "${CYAN}🏷️  Tags hiện có:${RESET}"
                git tag -l
                echo -e "${CYAN}📝 Nhập tên tag để xóa:${RESET}"
                read -r tag_name
            fi
            
            git tag -d "$tag_name"
            echo -e "${GREEN}✅ Đã xóa tag local: $tag_name${RESET}"
            echo -e "${YELLOW}💡 Chạy ${CYAN}git push $REMOTE :refs/tags/$tag_name${YELLOW} để xóa tag remote${RESET}"
            ;;
        *)
            echo -e "${RED}❌ Lệnh không hợp lệ${RESET}"
            echo -e "${CYAN}Sử dụng:${RESET}"
            echo -e "  ${GREEN}./git.sh tag${RESET}              - List tags"
            echo -e "  ${GREEN}./git.sh tag create v1.0.0${RESET} - Tạo tag"
            echo -e "  ${GREEN}./git.sh tag push v1.0.0${RESET}   - Push tag"
            echo -e "  ${GREEN}./git.sh tag delete v1.0.0${RESET} - Xóa tag"
            exit 1
            ;;
    esac
}

# ====== STASH ======
manage_stash() {
    local action="$1"
    
    case "$action" in
        save|s|"")  
            local msg="$2"
            if [[ -z "$msg" ]]; then
                git stash
            else
                git stash push -m "$msg"
            fi
            echo -e "${GREEN}✅ Đã stash thay đổi${RESET}"
            ;;
        list|l)
            echo -e "${CYAN}📦 Danh sách stash:${RESET}"
            git stash list
            ;;
        pop|p)
            git stash pop
            echo -e "${GREEN}✅ Đã apply và xóa stash gần nhất${RESET}"
            ;;
        apply|a)
            local stash_index="${2:-0}"
            git stash apply "stash@{$stash_index}"
            echo -e "${GREEN}✅ Đã apply stash@{$stash_index}${RESET}"
            ;;
        drop|d)
            local stash_index="${2:-0}"
            git stash drop "stash@{$stash_index}"
            echo -e "${GREEN}✅ Đã xóa stash@{$stash_index}${RESET}"
            ;;
        clear|c)
            echo -e "${YELLOW}⚠️  CẢNH BÁO: Xóa tất cả stash!${RESET}"
            echo -e "${CYAN}Bạn có chắc chắn? (y/N):${RESET}"
            read -r confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                git stash clear
                echo -e "${GREEN}✅ Đã xóa tất cả stash${RESET}"
            else
                echo -e "${YELLOW}⚠️  Đã hủy${RESET}"
            fi
            ;;
        *)
            echo -e "${RED}❌ Lệnh không hợp lệ${RESET}"
            echo -e "${CYAN}Sử dụng:${RESET}"
            echo -e "  ${GREEN}./git.sh stash${RESET}         - Stash thay đổi"
            echo -e "  ${GREEN}./git.sh stash list${RESET}    - Xem danh sách"
            echo -e "  ${GREEN}./git.sh stash pop${RESET}     - Apply & xóa"
            echo -e "  ${GREEN}./git.sh stash apply 0${RESET} - Apply stash index"
            exit 1
            ;;
    esac
}

# ====== DIFF ======
show_diff() {
    local target="$1"
    
    if [[ -z "$target" ]]; then
        echo -e "${CYAN}📊 Changes chưa staged:${RESET}"
        git diff --color=always
        echo -e "\n${CYAN}📊 Changes đã staged:${RESET}"
        git diff --staged --color=always
    else
        echo -e "${CYAN}📊 Diff với $target:${RESET}"
        git diff "$target" --color=always
    fi
}

# ====== HELP ======
show_help() {
    echo -e "${MAGENTA}
    ╔═══════════════════════════════════════╗
    ║            🚀 GIT HELPER              ║
    ║         Smart Git Assistant           ║
    ╚═══════════════════════════════════════╝
    ${RESET}"
    
    echo -e "${YELLOW}📖 Cách sử dụng:${RESET}"
    echo -e "  ${GREEN}./git.sh init${RESET}                  - Khởi tạo repo & đồng bộ GitHub"
    echo -e "  ${GREEN}./git.sh commit 'msg'${RESET}          - Commit thay đổi với message"
    echo -e "  ${GREEN}./git.sh push [-f]${RESET}             - Push branch (thêm -f để force)"
    echo -e "  ${GREEN}./git.sh branch [name]${RESET}         - Tạo/chuyển branch mới"
    echo -e "  ${GREEN}./git.sh checkout [name]${RESET}       - Chuyển sang branch khác"
    echo -e "  ${GREEN}./git.sh merge [branch]${RESET}        - Merge branch hiện tại → branch đích"
    echo -e "  ${GREEN}./git.sh status${RESET}                - Xem trạng thái nhanh"
    echo -e "  ${GREEN}./git.sh diff [commit]${RESET}         - Xem thay đổi"
    echo -e "  ${GREEN}./git.sh history${RESET}               - Xem lịch sử commit"
    echo -e "  ${GREEN}./git.sh tag create v1.0.0${RESET}     - Tạo & quản lý tags"
    echo -e "  ${GREEN}./git.sh tag push v1.0.0${RESET}       - Push tags"
    echo -e "  ${GREEN}./git.sh tag push all${RESET}          - Push all tags"
    echo -e "  ${GREEN}./git.sh tag delete v1.0.0${RESET}     - Xóa tags"
    echo -e "  ${GREEN}./git.sh stash${RESET}                 - Stash thay đổi tạm thời"
    echo -e "  ${GREEN}./git.sh revert [hash]${RESET}         - Revert commit cụ thể"
    echo -e "  ${GREEN}./git.sh reset [hash]${RESET}          - Reset về commit cũ"
    echo -e "  ${GREEN}./git.sh help${RESET}                  - Hiển thị hướng dẫn này"
    
    echo -e "${BLUE}
    ╔═══════════════════════════════════════╗
    ║           🎯 AUTO-COMPLETE            ║
    ╚═══════════════════════════════════════╝
    ${RESET}"
    
    echo -e "  ${GREEN}./git.sh --install-completion${RESET}  - Cài đặt tab auto-complete"
    echo -e ""
    echo -e "${CYAN}💡 Sau khi cài đặt:${RESET}"
    echo -e "   • Chạy: ${YELLOW}source ~/.bashrc${RESET}"
    echo -e "   • Gõ: ${YELLOW}./git.sh comm${CYAN}[TAB] → ${GREEN}./git.sh commit${RESET}"
    echo -e "   • Gõ: ${YELLOW}./git.sh che${CYAN}[TAB] → ${GREEN}./git.sh checkout${RESET}"
    
    echo -e "${YELLOW}
    ╔═══════════════════════════════════════╗
    ║           📝 VÍ DỤ SỬ DỤNG            ║
    ╚═══════════════════════════════════════╝
    ${RESET}"
    
    echo -e "  ${CYAN}# Workflow cơ bản:${RESET}"
    echo -e "  ${GREEN}./git.sh init${RESET}                  # Khởi tạo project"
    echo -e "  ${GREEN}./git.sh branch feature-xyz${RESET}    # Tạo branch mới"
    echo -e "  # ... làm việc ..."
    echo -e "  ${GREEN}./git.sh commit 'Add feature xyz'${RESET}"
    echo -e "  ${GREEN}./git.sh push${RESET}"
    echo -e "  ${GREEN}./git.sh merge main${RESET}            # Merge vào main"
}

# ====== MAIN FLOW ======
case "$1" in
    --install-completion)
        # Đã xử lý ở hàm setup_autocomplete
        ;;
    init)
        setup_config
        init_repo
        ;;
    commit)
        setup_config
        do_commit "$2"
        ;;
    push)
        do_push "$2"
        ;;
    branch)
        create_branch "$2"
        ;;
    checkout)
        checkout_branch "$2"
        ;;
    merge)
        do_merge "$2"
        ;;
    history|log)
        show_history
        ;;
    revert)
        revert_commit "$2"
        ;;
    reset)
        reset_to_commit "$2"
        ;;
    tag)
        manage_tags "$2" "$3"
        ;;
    stash)
        manage_stash "$2" "$3"
        ;;
    diff)
        show_diff "$2"
        ;;
    status)
        show_status
        ;;
    ""|help|-h|--help)
        show_help
        ;;
    *)
        echo -e "${RED}❌ Lệnh không hợp lệ:${RESET} '$1'"
        echo -e "${CYAN}ℹ️  Chạy ${GREEN}./git.sh help${CYAN} để xem hướng dẫn${RESET}"
        exit 1
        ;;
esac
