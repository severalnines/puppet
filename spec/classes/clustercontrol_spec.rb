# spec/classes/clustercontrol_spec.rb
#
# Test levels:
#
#   LEVEL 1 - CATALOG COMPILATION
#     Verifies the Puppet catalog compiles without errors for a given OS.
#     Runs automatically on every git push via GitHub Actions.
#     Does NOT require a real VM.
#
#   LEVEL 2 - REAL VM VALIDATED
#     Full end-to-end deployment confirmed working on a real VM:
#       - Packages installed
#       - Services started
#       - cmon --init succeeded
#       - ccmgradm init succeeded
#       - ccsetup user created
#       - GUI registration page accessible
#
# Current validation status:
#
#   OS                  | Catalog | Real VM |
#   --------------------|---------|---------|
#   Rocky Linux 9       |   ✅    |   ✅    |
#   AlmaLinux 9         |   ✅    |   ⏳    | (pending)
#   RHEL 9              |   ✅    |   ⏳    | (pending)
#   Rocky Linux 8       |   ✅    |   ⏳    | (pending)
#   Ubuntu 24.04        |   ✅    |   ⏳    | (pending)
#   Ubuntu 22.04        |   ✅    |   ⏳    | (in progress)
#   Debian 12           |   ✅    |   ⏳    | (pending)
#
# RULE: Once an OS is Real VM Validated, mark it below and NEVER remove its test.
#

require 'spec_helper'

describe 'clustercontrol' do

  let(:params) do
    {
      'mysql_root_password' => 'TestRootPass123!',
      'cmon_mysql_password' => 'TestCmonPass123!',
    }
  end

  # =========================================================================
  # REAL VM VALIDATED - These OS deployments have been confirmed working
  # end-to-end on a real VM. DO NOT remove or weaken these tests.
  # =========================================================================

  context 'on Rocky Linux 9 [REAL VM VALIDATED]' do
    let(:facts) do
      {
        'os' => {
          'family'  => 'RedHat',
          'name'    => 'Rocky',
          'release' => { 'major' => '9', 'full' => '9.4' },
        },
        'networking' => { 'ip' => '10.10.16.13' },
        'memory'     => { 'system' => { 'total_bytes' => 4294967296 } },
      }
    end

    # Catalog must compile
    it { is_expected.to compile.with_all_deps }

    # Must use RedHat install path
    it { is_expected.to contain_class('clustercontrol::install::redhat') }
    it { is_expected.not_to contain_class('clustercontrol::install::debian') }

    # All 4 sub-classes must be included
    it { is_expected.to contain_class('clustercontrol::configure_mysql') }
    it { is_expected.to contain_class('clustercontrol::configure_mcc') }
    it { is_expected.to contain_class('clustercontrol::mcc') }

    # MariaDB must be used (not MySQL)
    it { is_expected.to contain_package('mariadb-server').with_ensure('present') }
    it { is_expected.to contain_package('mariadb').with_ensure('present') }
    it { is_expected.not_to contain_package('mysql-community-server') }

    # All 9 CC packages must be installed
    it { is_expected.to contain_package('clustercontrol-controller') }
    it { is_expected.to contain_package('clustercontrol-mcc') }
    it { is_expected.to contain_package('clustercontrol-proxy') }
    it { is_expected.to contain_package('clustercontrol-kuber-proxy') }
    it { is_expected.to contain_package('clustercontrol-ssh') }
    it { is_expected.to contain_package('clustercontrol-notifications') }
    it { is_expected.to contain_package('clustercontrol-cloud') }
    it { is_expected.to contain_package('clustercontrol-clud') }
    it { is_expected.to contain_package('s9s-tools') }

    # MariaDB service must be managed
    it { is_expected.to contain_service('mariadb').with_ensure('running') }
    it { is_expected.to contain_service('mariadb').with_enable(true) }

    # All CC services must be started
    it { is_expected.to contain_service('cmon').with_ensure('running') }
    it { is_expected.to contain_service('cmon-ssh').with_ensure('running') }
    it { is_expected.to contain_service('cmon-events').with_ensure('running') }
    it { is_expected.to contain_service('cmon-cloud').with_ensure('running') }
    it { is_expected.to contain_service('cmon-proxy').with_ensure('running') }
    it { is_expected.to contain_service('kuber-proxy').with_ensure('running') }

    # /etc/my.cnf must be managed
    it { is_expected.to contain_file('/etc/my.cnf') }

    # /etc/default/cmon must be created
    it { is_expected.to contain_file('/etc/default/cmon') }

    # cmon-init and mcc-init must exist
    it { is_expected.to contain_exec('cmon-init') }
    it { is_expected.to contain_exec('mcc-init') }

    # ccsetup user creation must exist
    it { is_expected.to contain_exec('create-ccsetup-user') }

    # Admin password sync helper must be shipped
    it { is_expected.to contain_file('/usr/local/sbin/sync_cmon_admin.sh') }

    # SELinux must be disabled
    it { is_expected.to contain_exec('disable-selinux-runtime') }
    it { is_expected.to contain_file('/etc/selinux/config') }

    # Severalnines repos must be configured
    it { is_expected.to contain_exec('download-severalnines-repo') }
    it { is_expected.to contain_exec('download-severalnines-cli-repo') }

    # RPC token must be generated
    it { is_expected.to contain_exec('generate-rpc-token') }
    it { is_expected.to contain_file('/var/lib/cmon') }

    # cmon markers must exist
    it { is_expected.to contain_exec('create-cmon-init-marker') }
    it { is_expected.to contain_exec('create-mcc-init-marker') }
  end

  # =========================================================================
  # CATALOG ONLY - Not yet validated on real VM
  # These tests ensure catalog compilation but real VM testing is pending.
  # Update status above when real VM testing is complete.
  # =========================================================================

  context 'on AlmaLinux 9 [CATALOG ONLY - pending real VM]' do
    let(:facts) do
      {
        'os' => {
          'family'  => 'RedHat',
          'name'    => 'AlmaLinux',
          'release' => { 'major' => '9', 'full' => '9.4' },
        },
        'networking' => { 'ip' => '10.10.16.13' },
        'memory'     => { 'system' => { 'total_bytes' => 4294967296 } },
      }
    end
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_class('clustercontrol::install::redhat') }
    it { is_expected.to contain_package('mariadb-server').with_ensure('present') }
    it { is_expected.to contain_package('clustercontrol-controller') }
    it { is_expected.to contain_service('cmon').with_ensure('running') }
  end

  context 'on RHEL 9 [CATALOG ONLY - pending real VM]' do
    let(:facts) do
      {
        'os' => {
          'family'  => 'RedHat',
          'name'    => 'RedHat',
          'release' => { 'major' => '9', 'full' => '9.4' },
        },
        'networking' => { 'ip' => '10.10.16.13' },
        'memory'     => { 'system' => { 'total_bytes' => 4294967296 } },
      }
    end
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_class('clustercontrol::install::redhat') }
    it { is_expected.to contain_package('mariadb-server').with_ensure('present') }
  end

  context 'on Rocky Linux 8 [CATALOG ONLY - pending real VM]' do
    let(:facts) do
      {
        'os' => {
          'family'  => 'RedHat',
          'name'    => 'Rocky',
          'release' => { 'major' => '8', 'full' => '8.9' },
        },
        'networking' => { 'ip' => '10.10.16.13' },
        'memory'     => { 'system' => { 'total_bytes' => 4294967296 } },
      }
    end
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_class('clustercontrol::install::redhat') }
    it { is_expected.to contain_package('mariadb-server').with_ensure('present') }
  end

  context 'on Ubuntu 22.04 [CATALOG ONLY - real VM in progress]' do
    let(:facts) do
      {
        'os' => {
          'family'  => 'Debian',
          'name'    => 'Ubuntu',
          'release' => { 'major' => '22.04', 'full' => '22.04' },
          'distro'  => { 'codename' => 'jammy' },
        },
        'networking' => { 'ip' => '10.10.16.13' },
        'memory'     => { 'system' => { 'total_bytes' => 4294967296 } },
      }
    end
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_class('clustercontrol::install::debian') }
    it { is_expected.not_to contain_class('clustercontrol::install::redhat') }
    it { is_expected.to contain_package('mariadb-server').with_ensure('present') }
    it { is_expected.to contain_package('clustercontrol-controller') }
    it { is_expected.to contain_service('cmon').with_ensure('running') }
  end

  context 'on Ubuntu 24.04 [CATALOG ONLY - pending real VM]' do
    let(:facts) do
      {
        'os' => {
          'family'  => 'Debian',
          'name'    => 'Ubuntu',
          'release' => { 'major' => '24.04', 'full' => '24.04' },
          'distro'  => { 'codename' => 'noble' },
        },
        'networking' => { 'ip' => '10.10.16.13' },
        'memory'     => { 'system' => { 'total_bytes' => 4294967296 } },
      }
    end
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_class('clustercontrol::install::debian') }
    it { is_expected.to contain_package('mariadb-server').with_ensure('present') }
  end

  context 'on Debian 12 [CATALOG ONLY - pending real VM]' do
    let(:facts) do
      {
        'os' => {
          'family'  => 'Debian',
          'name'    => 'Debian',
          'release' => { 'major' => '12', 'full' => '12.5' },
          'distro'  => { 'codename' => 'bookworm' },
        },
        'networking' => { 'ip' => '10.10.16.13' },
        'memory'     => { 'system' => { 'total_bytes' => 4294967296 } },
      }
    end
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_class('clustercontrol::install::debian') }
    it { is_expected.to contain_package('mariadb-server').with_ensure('present') }
  end

  # =========================================================================
  # NEGATIVE TESTS - Must always fail correctly
  # =========================================================================

  context 'on unsupported OS family' do
    let(:facts) do
      {
        'os' => {
          'family'  => 'Windows',
          'name'    => 'Windows',
          'release' => { 'major' => '10', 'full' => '10.0' },
        },
        'networking' => { 'ip' => '10.10.16.13' },
        'memory'     => { 'system' => { 'total_bytes' => 4294967296 } },
      }
    end
    it { is_expected.to compile.and_raise_error(/Unsupported OS family/) }
  end

end
