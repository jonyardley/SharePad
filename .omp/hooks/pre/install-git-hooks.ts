// Parity with the SessionStart hook in .claude/settings.json, which fires for
// Claude Code only: an OMP session in a fresh clone or worktree had no
// core.hooksPath, so the pre-commit secret scan (`just install-hooks` points
// core.hooksPath at .githooks) never ran.

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

interface HookContext {
	cwd?: string;
}

interface HookAPI {
	on: (
		event: "session_start",
		handler: (event: unknown, ctx: HookContext) => Promise<void> | void,
	) => void;
	logger?: { debug?: (message: string) => void };
}

export async function installGitHooks(cwd: string): Promise<void> {
	await run("just", ["install-hooks"], { cwd });
}

export default function hook(pi: HookAPI): void {
	pi.on("session_start", async (_event, ctx) => {
		try {
			await installGitHooks(ctx?.cwd ?? process.cwd());
		} catch (err) {
			// Fail open: a session started outside the repo must still start.
			pi.logger?.debug?.(`install-git-hooks skipped: ${String(err)}`);
		}
	});
}
