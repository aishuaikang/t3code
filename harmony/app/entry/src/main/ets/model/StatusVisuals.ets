export function statusLabel(status: string): string {
  switch (status) {
    case 'running': return '执行中';
    case 'waiting': return '等待处理';
    case 'queued': return '排队中';
    case 'completed': return '已完成';
    case 'failed': return '异常';
    case 'interrupted': return '已中断';
    case 'archived': return '已归档';
    case 'connected': return '已连接';
    case 'connecting': return '连接中';
    case 'syncing': return '同步中';
    case 'reconnecting': return '重连中';
    case 'offline': return '已断开';
    default: return '未开始';
  }
}

export function connectionProgressLabel(status: string, refreshingArchive: boolean = false): string {
  switch (status) {
    case 'connecting': return '正在连接';
    case 'reconnecting': return '正在重新连接';
    case 'syncing': return '正在同步';
    case 'connected': return refreshingArchive ? '正在同步归档' : '';
    default: return '';
  }
}

export function statusColor(status: string, background: string): string {
  const dark = parseInt(background.slice(1, 3), 16) < 128;
  switch (status) {
    case 'running': case 'syncing': return dark ? '#60A5FA' : '#1D4ED8';
    case 'waiting': case 'connecting': case 'reconnecting': return dark ? '#FBBF24' : '#92400E';
    case 'queued': return dark ? '#C4B5FD' : '#6D28D9';
    case 'completed': case 'connected': return dark ? '#4ADE80' : '#166534';
    case 'failed': return dark ? '#FCA5A5' : '#B91C1C';
    case 'interrupted': return dark ? '#FDBA74' : '#9A3412';
    case 'archived': return dark ? '#67E8F9' : '#155E75';
    default: return dark ? '#A1A1AA' : '#52525B';
  }
}
