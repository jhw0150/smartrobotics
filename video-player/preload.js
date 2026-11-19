const { contextBridge, ipcRenderer, webUtils } = require('electron');

contextBridge.exposeInMainWorld('native', {
  initialFiles: () => ipcRenderer.invoke('initial-files'),
  onOpenFiles: cb => ipcRenderer.on('open-files', (_e, files) => cb(files)),
  pathFor: file => webUtils.getPathForFile(file),
  describe: paths => ipcRenderer.invoke('describe', paths),
  embeddedSub: id => ipcRenderer.invoke('embedded-sub', id),
});
