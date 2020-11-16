 Facter.add("iptables") do
   setcode do
     if Facter::Util::Resolution.exec('test -f /sbin/iptables') then
       "true"
     else
       "false"
     end
   end
 end