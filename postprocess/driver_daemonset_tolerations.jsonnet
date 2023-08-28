local com = import 'lib/commodore.libjsonnet';

local inv = com.inventory();
local params = inv.parameters.csi_cloudscale;
local tolerations = params.driver_daemonset_tolerations;

local chartDir = std.extVar('output_path');

com.fixupDir(
  chartDir,
  function(obj)
    if obj.kind == 'DaemonSet' then
      obj {
        spec+: {
          template+: {
            spec+: {
              [if std.length(tolerations) > 0 then 'tolerations']+: [
                tolerations[name] {
                  key: name,
                }
                for name in std.objectFields(tolerations)
              ],
            },
          },
        },
      }
    else
      obj
)
