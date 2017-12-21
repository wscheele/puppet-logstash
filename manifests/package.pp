# This class manages the Logstash package.
#
# It is usually used only by the top-level `logstash` class. It's unlikely
# that you will need to declare this class yourself.
#
# @param [String] package_name
#   The name of the Logstash package in the package manager.
#
# @param [String] version
#   Install precisely this version from the package manager.
#
# @param [String] package_url
#   Get the package from this URL, not from the package manager.
#
# @example Include this class to ensure its resources are available.
#   include logstash::package
#
# @author https://github.com/elastic/puppet-logstash/graphs/contributors
#
class logstash::package(
  $package_url = $logstash::package_url,
  $version = $logstash::version,
  $package_name = $logstash::package_name,
  $package_provider_default = $logstash::package_provider_default,
  $download_base_url = "https://artifacts.elastic.co/downloads/logstash"
)
{
  Exec {
    path      => [ '/bin', '/usr/bin', '/usr/local/bin' ],
    cwd       => '/',
    tries     => 3,
    try_sleep => 10,
  }

  File {
    ensure => file,
    backup => false,
  }

  if $logstash::ensure == 'present' {
    # Check if we want to install a specific version.
    if $version {
      if $::osfamily == 'redhat' {
        # Prerelease RPM packages have tildes ("~") in their version strings,
        # which can be quite surprising to the user. Let them say:
        #   6.0.0-rc2
        # not:
        #   6.0.0~rc2
        $package_ensure = regsubst($version, '(\d+)-(alpha|beta|rc)(\d+)$', '\1~\2\3')
      }
      else {
        $package_ensure = $version
      }
    }
    else {
      $package_ensure = $logstash::auto_upgrade ? {
        true  => 'latest',
        false => 'present',
      }
    }

    if ($package_url) {
      $filename = basename($package_url)
      $extension = regsubst($filename, '.*\.', '')
      $protocol = regsubst($package_url, ':.*', '')
      $package_local_file = "/tmp/${filename}"

      case $protocol {
        'puppet': {
          file { $package_local_file:
            source => $package_url,
          }
        }
        'ftp', 'https', 'http': {
          exec { "download_package_logstash_${name}":
            command => "wget -O ${package_local_file} ${package_url} 2> /dev/null",
            path    => ['/usr/bin', '/bin'],
            creates => $package_local_file,
            timeout => $logstash::download_timeout,
          }
        }
        'file': {
          file { $package_local_file:
            source => $package_url,
          }
        }
        default: {
          fail("Protocol must be puppet, file, http, https, or ftp. Not '${protocol}'")
        }
      }

      case $extension {
        'deb':   { $package_provider = 'dpkg'  }
        'rpm':   { $package_provider = 'rpm'   }
        default: { fail("Unknown file extension '${extension}'.") }
      }

      $package_require = undef
    }
    else {
      # Use the OS packaging system to locate the package.
      $package_local_file = undef
      $package_provider = undef
      if $::osfamily == 'Debian' {
        $package_require = Class['apt::update']
      } else {
        $package_require = undef
      }
    }
  }
  else { # Package removal
    $package_local_file = undef
    $package_require = undef
    if ($::osfamily == 'Suse') {
      $package_provider = 'rpm'
      $package_ensure = 'absent' # "purged" not supported by provider
    }
    else {
      $package_provider = $package_provider_default # ie. automatic
      $package_ensure = 'purged'
    }
  }

  case $::kernel {
    'Linux': {
      package { 'logstash':
        ensure   => $package_ensure,
        name     => $package_name,
        source   => $package_local_file, # undef if using package manager.
        provider => $package_provider, # undef if using package manager.
        require  => $package_require,
      }
    }
    'windows': {
      if $logstash::ensure == 'present' {
        archive {"C:\\Windows\\Temp\\logstash-${logstash::version}.zip":
          ensure       => present,
          source       => "${download_base_url}/logstash-${logstash::version}.zip",
          extract      => true,
          extract_path => inline_template("<%= Pathname.new(scope['logstash::home_dir']).parent %>"),
          creates      => $logstash::home_dir,
          cleanup      => true,
        } -> # add package resource for other resources to require
        package {'logstash':
          ensure => absent,
          require  => $package_require,
        }
      } else {
        file {$logstash::home_dir:
          ensure => absent,
        }
      }
    }
    default: {
      fail("${::kernel} not supported")
    }
  }
}
