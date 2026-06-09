import * as vue0 from "vue";
import { App, PropType, VNode } from "vue";

//#region src/FlowLayout.d.ts
declare const _default: vue0.DefineComponent<vue0.ExtractPropTypes<{
  cols: {
    type: PropType<number>;
    default: number;
  };
  gap: {
    type: PropType<number | [number, number]>;
    default: number;
  };
  duration: {
    type: PropType<boolean | number>;
    default: boolean;
  };
}>, () => VNode<vue0.RendererNode, vue0.RendererElement, {
  [key: string]: any;
}>, {}, {}, {}, vue0.ComponentOptionsMixin, vue0.ComponentOptionsMixin, {}, string, vue0.PublicProps, Readonly<vue0.ExtractPropTypes<{
  cols: {
    type: PropType<number>;
    default: number;
  };
  gap: {
    type: PropType<number | [number, number]>;
    default: number;
  };
  duration: {
    type: PropType<boolean | number>;
    default: boolean;
  };
}>> & Readonly<{}>, {
  cols: number;
  gap: number | [number, number];
  duration: number | boolean;
}, {}, {}, {}, string, vue0.ComponentProvideOptions, true, {}, any>;
//#endregion
//#region src/index.d.ts
declare const _default$1: {
  install: (app: App) => void;
};
//#endregion
export { _default as FlowLayout, _default$1 as default };