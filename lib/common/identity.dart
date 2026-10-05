const _useDevIdentity = bool.fromEnvironment('APP_DEV');

class AppIdentity {
  static const isDev = _useDevIdentity;

  static const productName = 'Bettbox';
  static const devSuffix = 'Dev';
  static const packageId = 'com.kevinchen222.bettbox.smart';

  static const compactName = isDev ? '$productName$devSuffix' : productName;
  static const displayName = isDev
      ? '$productName Smart Dev'
      : '$productName Smart';
  static const mainExecutableName = productName;
  static const coreExecutableName = '${compactName}Core';
  static const dataDirName = compactName;
  static const tunDeviceName = compactName;
}

class WindowsHelperIdentity {
  static const serviceName = '${AppIdentity.compactName}HelperService';
  static const pipeName = '\\\\.\\pipe\\${AppIdentity.compactName}.Helper';
}
