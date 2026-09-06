import Foundation

/// Moves system-owned files to the user's Trash through one administrator prompt per batch.
/// The work is a shell script run as root: launchd jobs are unloaded first, immutable flags
/// cleared, and the moved items handed to the user so the Trash can be emptied without
/// another prompt. Nothing is deleted.
public enum AdminRemover {
    public static func trash(_ urls: [URL]) -> [RemovalResult] {
        guard !urls.isEmpty else { return [] }
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let script = script(for: urls, trash: trash, uid: getuid(), gid: getgid())
        let encoded = Data(script.utf8).base64EncodedString()
        let command = "printf %s '\(encoded)' | /usr/bin/base64 --decode | /bin/bash -s"
        let appleScript = "do shell script \"\(command)\" with administrator privileges"
        do {
            let output = try Shell.run("/usr/bin/osascript", ["-e", appleScript], timeout: 900)
            return results(from: output, for: urls)
        } catch let failure as Shell.Failure {
            let message = failure.output.contains("-128")
                ? "No administrator password was given"
                : failure.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return urls.map { RemovalResult(url: $0, outcome: .failed(message)) }
        } catch {
            return urls.map { RemovalResult(url: $0, outcome: .failed(error.localizedDescription)) }
        }
    }

    static func script(for urls: [URL], trash: URL, uid: uid_t, gid: gid_t) -> String {
        let list = urls.map { quoted($0.path) }.joined(separator: "\n")
        return """
        trash=\(quoted(trash.path))
        uid=\(uid)
        gid=\(gid)
        paths=(
        \(list)
        )
        for p in "${paths[@]}"; do
          if [ ! -e "$p" ] && [ ! -L "$p" ]; then printf 'MISSING\\t%s\\n' "$p"; continue; fi
          name=${p##*/}
          case "$p" in
            /Library/LaunchDaemons/*.plist) /bin/launchctl bootout system "$p" >/dev/null 2>&1 ;;
            /Library/LaunchAgents/*.plist) /bin/launchctl bootout "gui/$uid" "$p" >/dev/null 2>&1 ;;
            /Library/PrivilegedHelperTools/*) /bin/launchctl bootout "system/$name" >/dev/null 2>&1 ;;
          esac
          /usr/bin/chflags -R nouchg,noschg "$p" >/dev/null 2>&1
          dest="$trash/$name"
          if [ -e "$dest" ] || [ -L "$dest" ]; then
            stamp=$(/bin/date +%H.%M.%S)
            dest="$trash/$name $stamp"
            n=2
            while [ -e "$dest" ] || [ -L "$dest" ]; do dest="$trash/$name $stamp $n"; n=$((n + 1)); done
          fi
          if err=$(/bin/mv "$p" "$dest" 2>&1); then
            /usr/sbin/chown -R "$uid:$gid" "$dest" >/dev/null 2>&1
            printf 'OK\\t%s\\t%s\\n' "$p" "$dest"
          else
            printf 'FAIL\\t%s\\t%s\\n' "$p" "$err"
          fi
        done
        """
    }

    static func results(from output: String, for urls: [URL]) -> [RemovalResult] {
        var byPath: [String: RemovalResult.Outcome] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2 else { continue }
            switch fields[0] {
            case "OK": byPath[fields[1]] = .trashed(URL(fileURLWithPath: fields.count > 2 ? fields[2] : fields[1]))
            case "MISSING": byPath[fields[1]] = .failed("Already gone")
            default: byPath[fields[1]] = .failed(fields.count > 2 ? fields[2] : "Could not move")
            }
        }
        return urls.map { RemovalResult(url: $0, outcome: byPath[$0.path] ?? .failed("No result reported")) }
    }

    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
