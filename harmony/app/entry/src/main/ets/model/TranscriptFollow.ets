/** Follow new content until the user starts reading history. Layout changes may arrive after the data. */
export class TranscriptFollow {
  following: boolean = true;
  private pending: boolean = false;
  private touching: boolean = false;
  private content: string = '';
  update(content: string): void {
    if (this.content === content) return;
    this.content = content;
    if (this.following) this.pending = true;
  }
  resized(): void { if (this.following) this.pending = true; }
  pause(): void { this.following = false; this.pending = false; }
  // Holding still defers a follow request without changing the reader's position or intent.
  touchStart(): void { this.touching = true; }
  touchEnd(): void { this.touching = false; }
  jump(): void { this.following = true; this.pending = true; }
  viewport(atBottom: boolean, userScroll: boolean = false): void {
    if (!userScroll) return;
    if (atBottom) this.following = true;
    else this.pause();
  }
  takeRequest(): boolean {
    if (this.touching || !this.pending || !this.following) return false;
    this.pending = false;
    return true;
  }
}
