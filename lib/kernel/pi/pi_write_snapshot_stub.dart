typedef WriteSnapshot = ({bool existed, String? content});

String displayPath(String path) => path;

WriteSnapshot readBeforeWrite(String path) => (existed: false, content: null);
