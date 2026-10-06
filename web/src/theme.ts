import type { ThemeConfig } from 'antd';

/**
 * The product's visual system: a near-black slate chrome, a light working canvas and
 * one accent colour. Flat surfaces, hairline borders, restrained shadows — colour means
 * something (status, identity) rather than decorating.
 * index.css mirrors these values as CSS variables for the parts antd does not cover.
 */

export const brand = {
  accent: '#0d9488', // teal 600 — primary actions and active states
  accentDark: '#0f766e',
  accentSoft: '#effbf8',
  chrome: '#111827', // sidebar + header
  chromeSoft: '#1f2937',
  text: '#111827',
  textSoft: '#4b5563',
  muted: '#9ca3af',
  border: '#e5e7eb',
  borderSoft: '#f1f2f4',
  surface: '#ffffff',
  layout: '#f6f7f9',
  success: '#15803d',
  warning: '#b45309',
  error: '#be123c',
};

/**
 * Categorical chart colours, assigned in this fixed order and never cycled.
 * Checked with the dataviz validator: lightness band, chroma floor, colour-blind
 * separation, normal-vision separation and contrast all pass on a light surface.
 */
export const series = ['#0d9488', '#be123c', '#0369a1', '#b45309', '#6d28d9', '#15803d'];

/** Status colours for pass / coverage scales; always shown with a number beside them. */
export const status = { good: '#15803d', warning: '#b45309', critical: '#be123c' };

const sans = "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif";

export const theme: ThemeConfig = {
  token: {
    colorPrimary: brand.accent,
    colorInfo: brand.accent,
    colorSuccess: brand.success,
    colorWarning: brand.warning,
    colorError: brand.error,
    colorTextBase: brand.text,
    colorBgLayout: brand.layout,
    colorBorder: brand.border,
    colorBorderSecondary: brand.borderSoft,
    colorLink: brand.accentDark,
    fontFamily: sans,
    fontSize: 14,
    borderRadius: 10,
    borderRadiusLG: 14,
    borderRadiusSM: 8,
    controlHeight: 38,
    lineHeight: 1.57,
    wireframe: false,
    boxShadowTertiary: '0 1px 2px rgba(16, 24, 40, 0.04)',
  },
  components: {
    Layout: { headerBg: 'transparent', siderBg: 'transparent', bodyBg: brand.layout, headerHeight: 60, headerPadding: '0 20px' },
    // The sidebar runs antd's dark menu over the slate chrome set in index.css.
    // The current page is tinted with the accent rather than plain white, so the brand
    // colour carries the "you are here" signal instead of decorating.
    Menu: {
      itemHeight: 40,
      itemMarginInline: 10,
      itemMarginBlock: 2,
      itemBorderRadius: 9,
      iconSize: 17,
      collapsedIconSize: 18,
      groupTitleFontSize: 10.5,
      darkItemBg: 'transparent',
      darkSubMenuItemBg: 'transparent',
      darkItemColor: '#98a2b3',
      darkItemHoverBg: 'rgba(255, 255, 255, 0.05)',
      darkItemHoverColor: '#ffffff',
      darkItemSelectedBg: 'rgba(13, 148, 136, 0.16)',
      darkItemSelectedColor: '#ffffff',
      darkGroupTitleColor: '#5b6677',
    },
    Card: { borderRadiusLG: 14, paddingLG: 20, headerFontSize: 15, headerHeight: 54, boxShadowTertiary: 'none' },
    Table: {
      headerBg: '#fafafa',
      headerColor: '#6b7280',
      headerSplitColor: 'transparent',
      rowHoverBg: '#fafafa',
      borderColor: brand.borderSoft,
      cellPaddingBlock: 12,
      cellPaddingBlockSM: 9,
      footerBg: '#fafafa',
    },
    // A primary button carries one soft shadow so it reads as the thing to press;
    // secondary and danger stay flat so a screen never has two competing emphases.
    Button: {
      fontWeight: 500,
      paddingInline: 17,
      primaryShadow: '0 1px 2px rgba(16, 24, 40, 0.10)',
      defaultShadow: 'none',
      dangerShadow: 'none',
      defaultBorderColor: brand.border,
    },
    Input: { paddingBlock: 7 },
    Select: { optionSelectedBg: brand.accentSoft },
    Tabs: { itemSelectedColor: brand.text, titleFontSize: 14, horizontalItemGutter: 22, inkBarColor: brand.accent },
    Tag: { borderRadiusSM: 6, defaultBg: '#f2f4f7', defaultColor: brand.textSoft },
    Statistic: { contentFontSize: 26, titleFontSize: 13 },
    Modal: { borderRadiusLG: 16, headerBg: 'transparent', titleFontSize: 16 },
    Drawer: { paddingLG: 20 },
    Segmented: { itemSelectedBg: '#ffffff', trackBg: '#f3f4f6', itemSelectedColor: brand.text, borderRadius: 7 },
    Tooltip: { borderRadius: 6, colorBgSpotlight: '#111827' },
    Progress: { defaultColor: brand.accent },
    Avatar: { containerSize: 34 },
    Alert: { borderRadiusLG: 10, withDescriptionPadding: '14px 16px' },
    Descriptions: { labelBg: '#fafafa', titleMarginBottom: 12, itemPaddingBottom: 12 },
    List: { itemPadding: '14px 0' },
    Notification: { borderRadiusLG: 10 },
    Message: { borderRadiusLG: 8 },
  },
};
