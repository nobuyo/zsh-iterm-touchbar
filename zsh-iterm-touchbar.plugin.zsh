# GIT
GIT_UNCOMMITTED="${GIT_UNCOMMITTED:-+}"
GIT_UNSTAGED="${GIT_UNSTAGED:-!}"
GIT_UNTRACKED="${GIT_UNTRACKED:-?}"
GIT_STASHED="${GIT_STASHED:-$}"
GIT_UNPULLED="${GIT_UNPULLED:-⇣}"
GIT_UNPUSHED="${GIT_UNPUSHED:-⇡}"

# Output name of current branch.
git_current_branch() {
  local ref
  ref=$(command git symbolic-ref --quiet HEAD 2> /dev/null)
  local ret=$?
  if [[ $ret != 0 ]]; then
    [[ $ret == 128 ]] && return  # no git repo.
    ref=$(command git rev-parse --short HEAD 2> /dev/null) || return
  fi
  echo ${ref#refs/heads/}
}

# Uncommitted changes.
# Check for uncommitted changes in the index.
git_uncomitted() {
  if ! $(git diff --quiet --ignore-submodules --cached); then
    echo -n "${GIT_UNCOMMITTED}"
  fi
}

# Unstaged changes.
# Check for unstaged changes.
git_unstaged() {
  if ! $(git diff-files --quiet --ignore-submodules --); then
    echo -n "${GIT_UNSTAGED}"
  fi
}

# Untracked files.
# Check for untracked files.
git_untracked() {
  if [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo -n "${GIT_UNTRACKED}"
  fi
}

# Stashed changes.
# Check for stashed changes.
git_stashed() {
  if $(git rev-parse --verify refs/stash &>/dev/null); then
    echo -n "${GIT_STASHED}"
  fi
}

# Unpushed and unpulled commits.
# Get unpushed and unpulled commits from remote and draw arrows.
git_unpushed_unpulled() {
  # check if there is an upstream configured for this branch
  command git rev-parse --abbrev-ref @'{u}' &>/dev/null || return

  local count
  count="$(command git rev-list --left-right --count HEAD...@'{u}' 2>/dev/null)"
  # exit if the command failed
  (( !$? )) || return

  # counters are tab-separated, split on tab and store as array
  count=(${(ps:\t:)count})
  local arrows left=${count[1]} right=${count[2]}

  (( ${right:-0} > 0 )) && arrows+="${GIT_UNPULLED}"
  (( ${left:-0} > 0 )) && arrows+="${GIT_UNPUSHED}"

  [ -n $arrows ] && echo -n "${arrows}"
}

pecho() {
  if [ -n "$TMUX" ]
  then
    echo -ne "\ePtmux;\e$*\e\\"
  else
    echo -ne $*
  fi
}

# F1-12: https://github.com/vmalloc/zsh-config/blob/master/extras/function_keys.zsh
fnKeys=('^[OP' '^[OQ' '^[OR' '^[OS' '^[[15~' '^[[17~' '^[[18~' '^[[19~' '^[[20~' '^[[21~' '^[[23~' '^[[24~')
touchBarState=''
npmScripts=()
makeRules=()
gitBranches=()
lastPackageJsonPath=''
lastMakefilePath=''

function _clearTouchbar() {
  pecho "\033]1337;PopKeyLabels\a"
}

function _unbindTouchbar() {
  for fnKey in "$fnKeys[@]"; do
    bindkey -s "$fnKey" ''
  done
}

function _displayDefault() {
  _clearTouchbar
  _unbindTouchbar

  touchBarState=''

  # CURRENT_DIR
  # -----------
  pecho "\033]1337;SetKeyLabel=F1=👉 $(echo $(pwd) | awk -F/ '{print $(NF-1)"/"$(NF)}')\a"
  bindkey -s '^[OP' 'pwd \n'

  # GIT
  # ---
  # Check if the current directory is in a Git repository.
  # command git rev-parse --is-inside-work-tree &>/dev/null || return

  # Check if the current directory is in .git before running git checks.
  if [[ "$(git rev-parse --is-inside-git-dir 2> /dev/null)" == 'false' ]]; then

    # Ensure the index is up to date.
    git update-index --really-refresh -q &>/dev/null

    # String of indicators
    local indicators=''

    indicators+="$(git_uncomitted)"
    indicators+="$(git_unstaged)"
    indicators+="$(git_untracked)"
    indicators+="$(git_stashed)"
    indicators+="$(git_unpushed_unpulled)"

    [ -n "${indicators}" ] && touchbarIndicators="🔥[${indicators}]" || touchbarIndicators="🙌";

    pecho "\033]1337;SetKeyLabel=F2=🎋 $(git_current_branch)\a"
    pecho "\033]1337;SetKeyLabel=F3=$touchbarIndicators\a"
    pecho "\033]1337;SetKeyLabel=F4=👀\a";
    pecho "\033]1337;SetKeyLabel=F5=🗑\a";

    # bind git actions
    bindkey "${fnKeys[2]}" _displayBranches
    bindkey -s "${fnKeys[3]}" 'git status -s \n'
    bindkey -s "${fnKeys[4]}" "git diff \n"
    bindkey -s "${fnKeys[5]}" "git branch | grep -v '*' | grep -v 'master' | xargs git branch -d \n"
  else
    pecho "\033]1337;SetKeyLabel=F2=⛔ not git yet\a";
  fi

  if [[ "$(git rev-parse --is-inside-git-dir 2> /dev/null)" == 'false' ]]; then
    toolsIndex=5
  else
    toolsIndex=3
  fi

  # PACKAGE.JSON
  # ------------
  if [[ -f package.json ]]; then
    if [[ -f yarn.lock ]]; then
        pecho "\033]1337;SetKeyLabel=F$toolsIndex=🐱 yarn-run\a"
        bindkey $fnKeys[$toolsIndex] _displayYarnScripts
    else
        pecho "\033]1337;SetKeyLabel=F$toolsIndex=⚡️ npm-run\a"
        bindkey $fnKeys[$toolsIndex] _displayNpmScripts
    fi
    toolsIndex=$((toolsIndex + 1))
  fi

  # MAKEFILE
  # ------------
  if [[ -f Makefile ]]; then
    pecho "\033]1337;SetKeyLabel=F$toolsIndex=🐒 make\a"
    bindkey $fnKeys[$toolsIndex] _displayMakeScripts
    toolsIndex=$((toolsIndex + 1))
  fi
}

function _displayNpmScripts() {
  # find available npm run scripts only if new directory
  if [[ $lastPackageJsonPath != $(echo "$(pwd)/package.json") ]]; then
    lastPackageJsonPath=$(echo "$(pwd)/package.json")
    if [[ -n "$(cat $lastPackageJsonPath)" ]]; then
      npmScripts=($(node -e "console.log(Object.keys($(npm run --json)).filter(name => !name.includes(':')).sort((a, b) => a.localeCompare(b)).filter((name, idx) => idx < 12).join(' '))"))
    fi
  fi

  _clearTouchbar
  _unbindTouchbar

  touchBarState='npm'
  
  if [[ -n "$npmScripts[@]" ]]; then
    fnKeysIndex=1
    for npmScript in "$npmScripts[@]"; do
      fnKeysIndex=$((fnKeysIndex + 1))
      bindkey -s $fnKeys[$fnKeysIndex] "npm run $npmScript \n"
      pecho "\033]1337;SetKeyLabel=F$fnKeysIndex=$npmScript\a"
    done
  else
    pecho "\033]1337;SetKeyLabel=F2=⛔ empty\a"
  fi

  pecho "\033]1337;SetKeyLabel=F1=👈 back\a"
  bindkey "${fnKeys[1]}" _displayDefault
}

function _displayYarnScripts() {
  # find available yarn run scripts only if new directory
  if [[ $lastPackageJsonPath != $(echo "$(pwd)/package.json") ]]; then
    lastPackageJsonPath=$(echo "$(pwd)/package.json")
    if [[ -n "$(cat $lastPackageJsonPath)" ]]; then
      yarnScripts=($(node -e "console.log($(yarn run --json 2>&1 | sed '4!d').data.items.filter(name => !name.includes(':')).sort((a, b) => a.localeCompare(b)).filter((name, idx) => idx < 12).join(' '))"))
    fi
  fi

  _clearTouchbar
  _unbindTouchbar

  touchBarState='yarn'

  if [[ -n "$npmScripts[@]" ]]; then
    fnKeysIndex=1
    for yarnScript in "$yarnScripts[@]"; do
      fnKeysIndex=$((fnKeysIndex + 1))
      bindkey -s $fnKeys[$fnKeysIndex] "yarn run $yarnScript \n"
      pecho "\033]1337;SetKeyLabel=F$fnKeysIndex=$yarnScript\a"
    done
  else
    pecho "\033]1337;SetKeyLabel=F2=⛔ empty\a"
  fi

  pecho "\033]1337;SetKeyLabel=F1=👈 back\a"
  bindkey "${fnKeys[1]}" _displayDefault
}

function _displayMakeScripts() {
  # find available makefile only if new directory
  if [[ $lastMakefilePath != $(echo "$(pwd)/Makefile") ]]; then
    lastMakefilePath=$(echo "$(pwd)/Makefile")
    if [[ -n "$(cat $lastMakefilePath)" ]]; then
      makeRules=($(node -e "console.log('$(echo $(cat Makefile | grep '^[^\.].*:' | cut -d':' -f1))')"))
    fi
  fi

  _clearTouchbar
  _unbindTouchbar

  touchBarState='make'

  if [[ -n "$makeRules[@]" ]]; then
    fnKeysIndex=1
    for makeRule in "$makeRules[@]"; do
      fnKeysIndex=$((fnKeysIndex + 1))
      bindkey -s $fnKeys[$fnKeysIndex] "make $makeRule \n"
      pecho "\033]1337;SetKeyLabel=F$fnKeysIndex=$makeRule\a"
    done
  else
    pecho "\033]1337;SetKeyLabel=F2=⛔ empty\a"
  fi

  pecho "\033]1337;SetKeyLabel=F1=👈 back\a"
  bindkey "${fnKeys[1]}" _displayDefault
}

function _displayBranches() {
  # List of branches for current repo
  gitBranches=($(node -e "console.log('$(echo master $(git branch --sort=-authordate | grep -v master | head -n 10))'.split(/[ ,]+/).toString().split(',').join(' ').toString().replace('* ', ''))"))

  _clearTouchbar
  _unbindTouchbar

  # change to github state
  touchBarState='github'

  fnKeysIndex=1
  # for each branch name, bind it to a key
  for branch in "$gitBranches[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    bindkey -s $fnKeys[$fnKeysIndex] "git checkout $branch \n"
    pecho "\033]1337;SetKeyLabel=F$fnKeysIndex=$branch\a"
  done

  pecho "\033]1337;SetKeyLabel=F1=👈 back\a"
  bindkey "${fnKeys[1]}" _displayDefault
}

zle -N _displayDefault
zle -N _displayNpmScripts
zle -N _displayYarnScripts
zle -N _displayMakeScripts
zle -N _displayBranches

precmd_iterm_touchbar() {
  if [[ $touchBarState == 'npm' ]]; then
    _displayNpmScripts
  elif [[ $touchBarState == 'yarn' ]]; then
    _displayYarnScripts
  elif [[ $touchBarState == 'make' ]]; then
    _displayMakeScripts
  elif [[ $touchBarState == 'github' ]]; then
    _displayBranches
  else
    _displayDefault
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd precmd_iterm_touchbar
