export const TokenSlimPlugin = async (_ctx, options) => {
    const mod = await import("file:///D:/AI%20Projects/OpenCode%20Token%20minimizer/dist/index.js");
    return (mod.default ?? mod.TokenSlim)(_ctx, options);
};
export default TokenSlimPlugin;