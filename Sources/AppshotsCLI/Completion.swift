import Foundation

/// `appshotsctl completion <zsh|bash>` — prints a shell completion script to
/// stdout. The hand-rolled parser has no spec to derive from, so these scripts
/// enumerate the subcommands, their sub-actions, and the `config` keys by hand;
/// keep them in sync with `main.swift` / the command files when commands change.
enum Completion {
    static func run(arguments: [String]) throws {
        guard let shell = arguments.first(where: { $0.hasPrefix("-") == false }) else {
            throw CLIError(message: "Usage: appshotsctl completion <zsh|bash>", exitCode: 2)
        }
        switch shell {
        case "zsh":
            print(zsh)
        case "bash":
            print(bash)
        default:
            throw CLIError(message: "Unsupported shell '\(shell)'. Use zsh or bash.", exitCode: 2)
        }
    }

    private static let zsh = """
    #compdef appshotsctl
    # Install: appshotsctl completion zsh > "${fpath[1]}/_appshotsctl" && compinit
    _appshotsctl() {
      local -a cmds
      cmds=(
        'capture:Capture the frontmost app'
        'benchmark:Capture repeatedly and print timings'
        'latest:Print the latest capture'
        'list:List recent captures (JSON)'
        'search:Search indexed captures'
        'delete:Delete a capture by id'
        'doctor:Permission + storage health checks'
        'mcp:MCP stdio server / install|uninstall|status'
        'daemon:Headless hot-key host'
        'config:Read/write ~/.appshots/config.json'
        'trigger:Show/set the capture trigger key'
        'sound:Toggle/show the capture sound'
        'update:Toggle/show auto-update'
        'startup:Manage launch-at-login'
        'onboarding:Report permission state'
        'completion:Print a shell completion script'
        'version:Print the version'
        'help:Show help'
      )
      if (( CURRENT == 2 )); then
        _describe 'command' cmds
        return
      fi
      case $words[2] in
        config)
          if (( CURRENT == 3 )); then
            _values 'subcommand' list get set unset path
          elif (( CURRENT == 4 )) && [[ $words[3] == (get|set|unset) ]]; then
            _values 'key' triggerKey captureSound copyOnCapture onboardingCompleted \\
              startupMode autoUpdate showInDock mcpDefaultScope mcpLastProjectDirectory \\
              postCaptureSendTarget
          fi ;;
        trigger) (( CURRENT == 3 )) && _values 'subcommand' get set reset ;;
        sound) (( CURRENT == 3 )) && _values 'subcommand' enable disable status ;;
        update) (( CURRENT == 3 )) && _values 'subcommand' auto ;;
        startup) (( CURRENT == 3 )) && _values 'subcommand' status enable disable ;;
        mcp) (( CURRENT == 3 )) && _values 'subcommand' install uninstall status ;;
        onboarding) (( CURRENT == 3 )) && _values 'subcommand' status ;;
        completion) (( CURRENT == 3 )) && _values 'shell' zsh bash ;;
      esac
    }
    _appshotsctl "$@"
    """

    private static let bash = """
    # appshotsctl bash completion
    # Install: appshotsctl completion bash > /usr/local/etc/bash_completion.d/appshotsctl
    _appshotsctl() {
      local cur prev cmds
      cur="${COMP_WORDS[COMP_CWORD]}"
      cmds="capture benchmark latest list search delete doctor mcp daemon config trigger sound update startup onboarding completion version help"
      if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$cmds" -- "$cur") ); return
      fi
      case "${COMP_WORDS[1]}" in
        config)
          if [ "$COMP_CWORD" -eq 2 ]; then
            COMPREPLY=( $(compgen -W "list get set unset path" -- "$cur") )
          elif [ "$COMP_CWORD" -eq 3 ]; then
            case "${COMP_WORDS[2]}" in
              get|set|unset) COMPREPLY=( $(compgen -W "triggerKey captureSound copyOnCapture onboardingCompleted startupMode autoUpdate showInDock mcpDefaultScope mcpLastProjectDirectory postCaptureSendTarget" -- "$cur") );;
            esac
          fi ;;
        trigger) [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "get set reset" -- "$cur") );;
        sound) [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "enable disable status" -- "$cur") );;
        update) [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "auto" -- "$cur") );;
        startup) [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "status enable disable" -- "$cur") );;
        mcp) [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "install uninstall status" -- "$cur") );;
        onboarding) [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "status" -- "$cur") );;
        completion) [ "$COMP_CWORD" -eq 2 ] && COMPREPLY=( $(compgen -W "zsh bash" -- "$cur") );;
      esac
    }
    complete -F _appshotsctl appshotsctl
    """
}
