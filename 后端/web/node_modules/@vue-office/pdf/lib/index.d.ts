declare const VueOfficePdf: {
    install?: (vue: any) => void;
    src: string|ArrayBuffer|Blob;
    rerender?: () => any;
    staticFileUrl?: string,
    requestOptions?: any;
    options?: any;
    getScale?: () => number;
    setScale?: (number) => void;
};
export default  VueOfficePdf;