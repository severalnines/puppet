require 'facter'

# Default for non-Linux nodes
#
Facter.add("controller_id") do
    setcode do
        nil
    end
end

# Linux
#
Facter.add("controller_id") do
    confine :kernel  => :linux
    setcode do
        if File.file?('/var/run/cmon.controller_id')
          Facter::Util::Resolution.exec("cat /var/run/cmon.controller_id")
        else
          Facter::Util::Resolution.exec("/usr/bin/uuidgen -tr|tr -d '\n' > /var/run/cmon.controller_id && cat /var/run/cmon.controller_id")
        end
    end
end