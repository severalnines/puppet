 Facter.add("is_gpg_installed") do
   setcode do
     if Facter::Util::Resolution.exec('which gpg') then
       "true"
     else
       "false"
     end
   end
 end