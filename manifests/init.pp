# init.pp

class zurmo (   $source,
                $installdir = '/opt/zurmo',
                $vhostname  = $fqdn,
                $dbhost     = 'localhost',
                $dbname     = 'zurmo',
                $dbuser     = 'zurmo',
                $dbpass     = false,
                $timezone   = 'America/Sao_Paulo'
             ) {

  if !$dbpass {
    fail("The following variables are mandatory: dbpass")
  }
   
  if $dbhost == 'localhost' {
    class { 'zurmo::database::mysql':
      ensure        => 'present',
      host          => 'localhost',
      password_hash => mysql_password("${dbpass}"),
      user          => $dbuser, 
      dbname        => $dbname, 
    }
  }

  if !defined(Class['apache']) {
    class { 'apache':
      mpm_module        => 'prefork',
      keepalive         => 'off',
      keepalive_timeout => '4',
      timeout           => '45',
    }
  }
  if !defined(Class['apache::mod::php']) {
    include apache::mod::php
  }

  exec { "create installdir":
    command => "mkdir -p $installdir",
    unless  => "test -d $installdir",
    path    => ["/bin", "/usr/bin", "/usr/sbin", "/usr/local/bin"],
  }

  file { "$installdir":
    ensure => directory,
    owner => 'www-data', group => 'root', mode => '664',
    recurse => true,
    require => Exec['create installdir'],
  }

  wget::fetch { "download zurmo":
    source => $source,
    destination => '/usr/local/src/zurmo.tar.gz',
    notify => Exec['unpack zurmo'],
  }

  exec { 'unpack zurmo':
    cwd => '/usr/local/src',
    command => "/bin/tar -xvzf /usr/local/src/zurmo.tar.gz -C ${installdir} --strip-components=1",
    creates => "${installdir}/index.php",
    require => Wget::Fetch['download zurmo'],
    #notify => Exec['vfense-agent install'],
  }

  # Vhost
  apache::vhost { $vhostname:
    port => '80',
    docroot => "$installdir",
    access_log_file => 'access_zurmo.log',
    error_log_file => 'error_zurmo.log',
    options => ['Indexes','FollowSymLinks'],
  }

  # Prereqs
  $pkgs = [ 'php5' ]
  ensure_packages ( $pkgs )

  # Memcached
  class { 'memcached':
    max_memory => 512
  }

  # PHP Cache Config
  php::module { [ 'apc', 
                  'mcrypt', 
                  'ldap',
                  'memcache',
                  'imap',
                  'mysql',
                  'curl',
                ]: }
  php::module::ini { 'apc':
    settings => {
      'apc.enabled'      => '1',
      'apc.shm_segments' => '1',
      'apc.shm_size'     => '128M',
      'apc.stat'         => '0',
    }
  }

  augeas { "/etc/php5/apache2/php.ini":
    changes => [
      "set date.timezone ${timezone}",
      "set memory_limit 256M",
      "set file_uploads On",
      "set upload_max_filesize 20M",
      "set post_max_size 20M",
      "set max_execution_time 300",
    ],
    context => "/files/etc/php5/apache2/php.ini/PHP",
  } 


}
