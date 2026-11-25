import { deviceInfo } from '@kit.BasicServicesKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';

export function menuIcon(symbol: Resource, tint?: ResourceColor): SymbolGlyphModifier {
  const icon = new SymbolGlyphModifier(symbol);
  if (tint !== undefined) icon.fontColor([tint]);
  return icon;
}

export function menuHapticFeedbackMode(): HapticFeedbackMode | undefined {
  return deviceInfo.sdkApiVersion >= 18 ? HapticFeedbackMode.ENABLED : undefined;
}

export function menuModalMode(): ModalMode | undefined {
  return deviceInfo.sdkApiVersion >= 20 ? ModalMode.TARGET_WINDOW : undefined;
}
