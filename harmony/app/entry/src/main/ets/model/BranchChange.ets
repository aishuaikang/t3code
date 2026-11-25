import { ThreadDetail } from './Models';
export interface CheckoutBranchMismatch { threadBranch: string; currentBranch: string; }
export interface BranchChange extends CheckoutBranchMismatch { key: string; }
export interface BranchNoticeInput {
  environmentId: string;
  cwd: string;
  thread: ThreadDetail | null;
  currentBranch: string;
  hasContent: boolean;
}

export function checkoutBranchMismatch(thread: ThreadDetail | null, currentBranch: string): CheckoutBranchMismatch | null {
  if (!thread?.branch || thread.worktreePath || !currentBranch || thread.branch === currentBranch) return null;
  return { threadBranch: thread.branch, currentBranch: currentBranch };
}

const dismissedBranchChanges: Set<string> = new Set();

export class BranchChangeNotice {
  private revealedKey: string = '';

  update(input: BranchNoticeInput): BranchChange | null {
    const mismatch = checkoutBranchMismatch(input.thread, input.currentBranch);
    if (mismatch === null) { this.revealedKey = ''; return null; }
    const key = JSON.stringify([input.environmentId, input.cwd, input.thread?.id, mismatch.threadBranch, mismatch.currentBranch]);
    if (this.revealedKey !== key) this.revealedKey = '';
    if (dismissedBranchChanges.has(key) || (!input.hasContent && this.revealedKey !== key)) return null;
    this.revealedKey = key;
    return { key: key, threadBranch: mismatch.threadBranch, currentBranch: mismatch.currentBranch };
  }

  dismiss(key: string): void { dismissedBranchChanges.add(key); }
}
