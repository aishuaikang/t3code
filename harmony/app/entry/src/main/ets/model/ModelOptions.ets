import { SubagentSummary, ModelSelection, ModelOptionDescriptor, ModelOptionChoice, ModelOptionSelection, ModelSwitch, ProviderInfo, ProviderModel } from './Models';

export function modelOptionChoices(descriptor: ModelOptionDescriptor): ModelOptionChoice[] {
  return (descriptor.options ?? []).filter((choice: ModelOptionChoice) =>
    choice.id !== 'ultracode' && !(descriptor.promptInjectedValues ?? []).includes(choice.id));
}

export function modelOptionValue(selection: ModelSelection, descriptor: ModelOptionDescriptor): string | boolean {
  const explicit = selection.options?.find((option: ModelOptionSelection) => option.id === descriptor.id);
  return explicit?.value ?? descriptor.currentValue ??
    (descriptor.type === 'boolean' ? false : descriptor.options?.find((choice: ModelOptionChoice) => choice.isDefault)?.id ?? '');
}

export function withModelOption(selection: ModelSelection, descriptor: ModelOptionDescriptor, value: string | boolean | null): ModelSelection | null {
  if (value !== null) {
    if (descriptor.type === 'boolean') { if (typeof value !== 'boolean') return null; }
    else if (descriptor.type === 'select') {
      if (typeof value !== 'string' || !modelOptionChoices(descriptor).some((choice: ModelOptionChoice) => choice.id === value)) return null;
    } else return null;
  }
  const options = (selection.options ?? []).filter((option: ModelOptionSelection) => option.id !== descriptor.id);
  if (value !== null) options.push({ id: descriptor.id, value: value });
  return { instanceId: selection.instanceId, model: selection.model, options: options };
}

export function reasoningOption(descriptors: ModelOptionDescriptor[]): ModelOptionDescriptor | undefined {
  return descriptors.find((descriptor: ModelOptionDescriptor) => descriptor.type === 'select' &&
    (descriptor.role === 'reasoning' || /reasoning|effort|thinking|推理|思考/i.test(`${descriptor.id} ${descriptor.label}`)) && modelOptionChoices(descriptor).length > 1);
}

export function fastModeOption(descriptors: ModelOptionDescriptor[]): ModelOptionDescriptor | undefined {
  return descriptors.find((descriptor: ModelOptionDescriptor) => descriptor.id === 'fastMode' && descriptor.type === 'boolean') ??
    descriptors.find((descriptor: ModelOptionDescriptor) => descriptor.id === 'serviceTier' && descriptor.type === 'select' &&
      modelOptionChoices(descriptor).length === 2 && modelOptionChoices(descriptor).some((choice: ModelOptionChoice) => choice.id === 'default') &&
      modelOptionChoices(descriptor).some((choice: ModelOptionChoice) => choice.id === 'priority'));
}

export function fastModeEnabled(selection: ModelSelection | null, descriptors: ModelOptionDescriptor[]): boolean {
  const descriptor = fastModeOption(descriptors);
  if (selection === null || descriptor === undefined) return false;
  const value = modelOptionValue(selection, descriptor);
  return descriptor.type === 'boolean' ? value === true : value === 'priority';
}

export function ultracodeOption(descriptors: ModelOptionDescriptor[]): ModelOptionDescriptor | undefined {
  return descriptors.find((descriptor: ModelOptionDescriptor) => descriptor.id === 'ultracode' && descriptor.type === 'boolean');
}

export function ultracodeEnabled(selection: ModelSelection | null, descriptors: ModelOptionDescriptor[]): boolean {
  const descriptor = ultracodeOption(descriptors);
  return selection !== null && descriptor !== undefined && modelOptionValue(selection, descriptor) === true;
}

const EFFORT_IDS: string[] = ['reasoningEffort', 'effort', 'reasoning', 'variant', 'reasoning_effort', 'thinking_level', 'thinking'];
interface SwitchEffort { value: string; label: string; }

function switchEffort(selection: ModelSelection, model: ProviderModel | undefined): SwitchEffort | null {
  if (model === undefined) {
    for (const id of EFFORT_IDS) {
      const value = selection.options?.find((option: ModelOptionSelection) => option.id === id)?.value;
      if (typeof value === 'string' && value) return { value: value, label: value };
    }
    return null;
  }
  const descriptor = model.capabilities?.optionDescriptors?.find((entry: ModelOptionDescriptor) =>
    entry.type === 'select' && (entry.role === 'reasoning' || EFFORT_IDS.includes(entry.id)));
  if (descriptor === undefined || (descriptor.id === 'variant' && !selection.options?.some((option: ModelOptionSelection) => option.id === descriptor.id))) return null;
  const value = modelOptionValue(selection, descriptor);
  return typeof value === 'string' && value ? { value: value,
    label: descriptor.options?.find((choice: ModelOptionChoice) => choice.id === value)?.label ?? value } : null;
}

export function modelSwitchLabel(change: ModelSwitch | undefined, providers: ProviderInfo[]): string {
  if (change === undefined) return '';
  const fromModel = providers.find((provider: ProviderInfo) => provider.instanceId === change.from.instanceId)
    ?.models.find((model: ProviderModel) => model.slug === change.from.model);
  const toModel = providers.find((provider: ProviderInfo) => provider.instanceId === change.to.instanceId)
    ?.models.find((model: ProviderModel) => model.slug === change.to.model);
  const fromEffort = switchEffort(change.from, fromModel), toEffort = switchEffort(change.to, toModel);
  const effortChanged = fromEffort !== null && toEffort !== null && fromEffort.value !== toEffort.value;
  if (change.from.model === change.to.model) return effortChanged ? `${fromEffort!.label} → ${toEffort!.label}` : '';
  const from = fromModel?.shortName || fromModel?.name || change.from.model;
  const to = toModel?.shortName || toModel?.name || change.to.model;
  return effortChanged ? `${from} ${fromEffort!.label} → ${to} ${toEffort!.label}` : `${from} → ${to}`;
}

export function subagentModelLabel(agent: SubagentSummary, providers: ProviderInfo[]): string {
  const selection = agent.modelSelection, instance = agent.providerInstanceId || selection?.instanceId;
  const provider = !agent.remoteChild ? providers.find(entry => entry.instanceId === instance) : undefined;
  const slug = agent.model || selection?.model;
  const model = provider?.models.find(entry => entry.slug === slug);
  const options = model?.capabilities?.optionDescriptors ?? [];
  const effort = selection?.options?.find(option => typeof option.value === 'string' &&
    (EFFORT_IDS.includes(option.id) || options.some(entry => entry.id === option.id && entry.role === 'reasoning')));
  const value = typeof effort?.value === 'string' ? effort.value : '';
  const label = options.find(entry => entry.id === effort?.id)?.options?.find(choice => choice.id === value)?.label;
  return [provider?.displayName || instance || agent.driver, model?.shortName || model?.name || slug,
    label || value.charAt(0).toUpperCase() + value.slice(1)].filter(part => !!part).join(' · ');
}
