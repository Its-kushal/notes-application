const { withAndroidManifest, withDangerousMod } = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

const dataExtractionRulesXml = `<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <exclude path="." />
    </cloud-backup>
    <device-transfer>
        <exclude path="." />
    </device-transfer>
</data-extraction-rules>
`;

function withAndroidSecurityConfig(config) {
  // 1. Ensure res/xml/data_extraction_rules.xml exists
  config = withDangerousMod(config, [
    'android',
    async (modConfig) => {
      const resXmlDir = path.join(
        modConfig.modRequest.platformProjectRoot,
        'app',
        'src',
        'main',
        'res',
        'xml'
      );
      if (!fs.existsSync(resXmlDir)) {
        fs.mkdirSync(resXmlDir, { recursive: true });
      }
      fs.writeFileSync(
        path.join(resXmlDir, 'data_extraction_rules.xml'),
        dataExtractionRulesXml,
        'utf-8'
      );
      return modConfig;
    },
  ]);

  // 2. Update AndroidManifest.xml
  config = withAndroidManifest(config, (modConfig) => {
    const app = modConfig.modResults.manifest.application?.[0];
    if (app) {
      app.$['android:allowBackup'] = 'false';
      app.$['android:fullBackupContent'] = 'false';
      app.$['android:dataExtractionRules'] = '@xml/data_extraction_rules';
    }
    return modConfig;
  });

  return config;
}

module.exports = withAndroidSecurityConfig;
