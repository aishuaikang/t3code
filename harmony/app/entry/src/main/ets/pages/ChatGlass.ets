import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ThemeRuntime } from '../connection/ThemeRuntime';

// Material thickness belongs to the surface. HarmonyOS chooses the light effect.
export function immersiveMaterial(usage: 'bar' | 'popup' | 'photo' | 'sheet' = 'bar', tint?: ResourceColor): uiMaterial.ImmersiveMaterial | undefined {
  if (deviceInfo.sdkApiVersion < 26 || !uiMaterial.isImmersiveMaterialSupported() ||
    uiMaterial.getMaterialInfo().state === uiMaterial.MaterialState.DISABLE) return undefined;
  return new uiMaterial.ImmersiveMaterial({
    style: usage === 'sheet' ? uiMaterial.ImmersiveStyle.THICK : usage === 'popup' ? uiMaterial.ImmersiveStyle.REGULAR : uiMaterial.ImmersiveStyle.THIN,
    materialColor: usage === 'photo' ? '#AB222228' : tint, applyShadow: false
  });
}

@Component
export struct ChatGlass {
  @Prop radius: number = 16;
  @Prop compact: boolean = false;
  @Prop capsule: boolean = false;
  @Prop onImage: boolean = false;
  @BuilderParam content: () => void;
  @StorageLink('themeKey') themeKey: string = 't3-code-light';
  private material: uiMaterial.ImmersiveMaterial | undefined = undefined;

  aboutToAppear(): void { this.material = immersiveMaterial(this.onImage ? 'photo' : 'bar'); }

  // A floating tab bar always draws a capsule. Use the custom tab item by default so taller content keeps the same corner radius.
  @Builder
  private roundedPanel() {
    Row() {}.width('100%').height('100%').borderRadius(this.radius).systemMaterial(this.material)
  }

  @Builder
  private reflectedColor(role: string, x: string, opacity: number) {
    Row() {}.height('100%').aspectRatio(1).constraintSize({ maxWidth: 132, maxHeight: 132 })
      .radialGradient({ center: ['50%', '50%'], radius: '50%', colors: [
        [ThemeRuntime.color(this.themeKey, role), 0], ['#00' + ThemeRuntime.color(this.themeKey, role).slice(1), 1]
      ] }).opacity(opacity).scale({ x: 4.8, y: 1.22 })
      .markAnchor({ x: '50%', y: '50%' }).position({ x: x, y: '50%' })
  }

  build() {
    if (this.material !== undefined) {
      Stack() {
        if (!this.compact && !this.onImage) {
          // Color the backdrop so the system glass can refract it; leave the material itself untinted.
          Stack() {
            this.reflectedColor('glass-depth', '24%', this.themeKey.endsWith('-dark') ? 0.60 : 0.72)
            this.reflectedColor('glass-glow', '77%', this.themeKey.endsWith('-dark') ? 0.44 : 0.82)
          }.width('100%').height(LayoutPolicy.matchParent)
            .focusable(false).accessibilityLevel('no-hide-descendants').hitTestBehavior(HitTestMode.None)
        }
        // The native floating bar is measured against the live controls, including a growing draft.
        Tabs({ barPosition: BarPosition.End }) {
          if (this.capsule) { TabContent() {}.tabBar('') }
          else { TabContent() {}.tabBar(this.roundedPanel()) }
        }.width(this.compact ? LayoutPolicy.matchParent : '100%').height(LayoutPolicy.matchParent).barWidth('100%').barHeight('100%')
          .barBackgroundColor(Color.Transparent)
          .barFloatingStyle(this.capsule ? { systemMaterial: this.material, barSideMargin: 0, barBottomMargin: 0,
            maskColor: Color.Transparent, maskHeight: 0 } : undefined).barOverlap(this.capsule).divider(null).scrollable(false)
          .backgroundColor(Color.Transparent).borderRadius(this.radius).clip(true)
          .focusable(false).accessibilityLevel('no-hide-descendants').hitTestBehavior(HitTestMode.None)
        this.content()
      }.width(this.compact ? LayoutPolicy.wrapContent : '100%').height(LayoutPolicy.wrapContent).borderRadius(this.radius).clip(true)
    } else {
      Stack() { this.content() }.width(this.compact ? 'auto' : '100%').borderRadius(this.radius)
        .backgroundColor(this.onImage ? '#29292D' : ThemeRuntime.color(this.themeKey, 'card')).clip(true)
    }
  }
}

@Component
export struct ChatPageHeader {
  @BuilderParam content: () => void;

  build() {
    Column() {
      ChatGlass({ radius: 26 }) {
        Stack() { this.content() }.width('100%').constraintSize({ minHeight: 52 })
      }
    }.width('100%').padding({ left: 16, right: 16, top: 4 })
  }
}
