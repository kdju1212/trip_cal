'use strict';
window.TripImageRatio = {
  isSquare(file) {
    return new Promise(resolve => {
      let url;
      try {
        url = URL.createObjectURL(file);
        const image = new Image();
        image.onload = () => { URL.revokeObjectURL(url); resolve(image.naturalWidth > 0 && image.naturalWidth === image.naturalHeight); };
        image.onerror = () => { URL.revokeObjectURL(url); resolve(false); };
        image.src = url;
      } catch (_) {
        if (url) URL.revokeObjectURL(url);
        resolve(false);
      }
    });
  },
};
