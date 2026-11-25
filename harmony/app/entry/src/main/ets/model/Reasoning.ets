export function reasoningTitle(text: string, streaming: boolean): string {
  const first = text.split('\n').find((line: string) => !!line.trim()) ?? '';
  const title = first.replace(/^\s*#{1,6}\s+/, '').replace(/\*\*/g, '').trim();
  return streaming ? (title ? `思考中 · ${title}` : '思考中…') : (title || '思考过程');
}
export function reasoningBody(text: string): string {
  return text.replace(/^\s*#{1,6}\s+/gm, '').replace(/\*\*(.*?)\*\*/g, '$1').trim();
}
