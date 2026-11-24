const _useDevIdentity = bool.fromEnvironment('APP_DEV');
const _useStandardBuild = bool.fromEnvironment('APP_STANDARD');

class AppIdentity {
  static const isDev = _useDevIdentity;
  static const isStandard = _useStandardBuild;

  static const productName = 'Bettbox';
  static const devSuffix = 'Dev';
  static const packageId = 'com.vela';

  static const compactName = isDev ? '$productName$devSuffix' : productName;
  static const displayName = isDev ? 'Vela Dev' : 'Vela';
  static const mainExecutableName = productName;
  static const coreExecutableName = '${compactName}Core';
  static const dataDirName = compactName;
  static const tunDeviceName = compactName;
}

class WindowsHelperIdentity {
  static const serviceName = '${AppIdentity.compactName}HelperService';
  static const pipeName = '\\\\.\\pipe\\${AppIdentity.compactName}.Helper';
}
