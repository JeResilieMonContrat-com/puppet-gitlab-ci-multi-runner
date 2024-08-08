# == Class: gitlab_ci_multi_runner
#
# Install gitlab-ci multi runner (package, service)
#
# === Parameters
#
# [*version*]
#   A version for the gitlab-ci-multi-runner package. This can be to a specfic
#   version number, present (if you don't want Puppet to update it for you) or
#   latest.
#
#   The version of the package will always be set to v0.4.2 for RHEL5 and RHEL
#   6 derivatives.
#   Default: latest
#
# [*env*]
#   Pass environment vars to the execs
#   Useful for a proxy or the like.
#   Default: undef.
#
# [*manage_user*]
#   Do you want to manage the user
#   You may want to turn off if you use root.
#   Default: true.
#
# [*user*]
#   The user to manage or run as
#   You may want to use root.
#   Default: gitlab_ci_multi_runner.
#
# === Examples
#
#  include '::gitlab_ci_multi_runner'
#
class gitlab_ci_multi_runner (
    $package_name = 'gitlab-runner',
    $env = undef,
    $manage_user = true,
    $user = 'gitlab_ci_multi_runner',
    $version = 'latest'
) {
    $package_type = $facts['os']['family'] ? {
        'redhat' => 'rpm',
        'debian' => 'deb',
        default  => 'unknown',
    }
    $issues_link = 'https://github.com/frankiethekneeman/puppet-gitlab-ci-multi-runner/issues'
    if $package_type == 'unknown' {
        fail("Target Operating system (${$facts['os']['name']}) not supported")
    }

    $service_file = $package_type ? {
        'rpm'   => $facts['os']['release']['full'] ? {
            /^(5.*|6.*)/ => '/etc/init.d/gitlab-ci-multi-runner',
            default      => '/etc/systemd/system/gitlab-runner.service',
        },
        'deb'   => $facts['os']['release']['full'] ? {
            /^(14.*|7.*)/ => '/etc/init/gitlab-runner.conf',
            default => '/etc/systemd/system/gitlab-runner.service',
        },
        default => '/bin/true',
    }

    if !$version {
        $theVersion = $facts['os']['family'] ? {
            'redhat' => $facts['os']['release']['full'] ? {
                /^(5.*|6.*)/ => '0.4.2-1',
                default      => 'latest',
            },
            'debian' => 'latest',
            default  => 'There is no spoon',
        }
    } else {
        $theVersion = $version

    }

    $service = $theVersion ? {
        '0.4.2-1' => 'gitlab-ci-multi-runner',
        default   => 'gitlab-runner',
    }

    $home_path = $user ? {
        'root'  => '/root',
        default => "/home/${user}",
    }

    $toml_path = $user ? {
        'root'  => '/etc/gitlab-runner',
        default => $::gitlab_ci_multi_runner::version ? {
            /^0\.[0-4]\..*/ => $home_path,
            default         => "${home_path}/.gitlab-runner",
        },
    }

    $toml_file = "${toml_path}/config.toml"

    if $env { Exec { environment => $env } }

    # Ensure the gitlab_ci_multi_runner user exists.
    # TODO:  Investigate if this is necessary - install script may handle this.
    if $manage_user {
      user { $user:
          ensure     => 'present',
          managehome => true,
          before     => Exec['Add Repository'],
      }
    }

    package { $package_name:
        ensure => $theVersion,
    } ->
    exec { 'Uninstall Misconfigured Service':
        command  => "service ${service} stop; ${service} uninstall",
        user     => root,
        provider => shell,
        unless   => "grep '${toml_file}' ${service_file}",
    } ->
    exec { 'Ensure Service':
        command  => "${service} install --user ${user} --config ${toml_file} --working-directory ${home_path}",
        user     => root,
        provider => shell,
        creates  => $service_file,
    } ->
    file { 'Ensure .gitlab-runner directory is owned by correct user':
        path    => $toml_path,
        owner   => $user,
        recurse => true,
    } ->
    # Ensure that the service is running at all times.
    service { $service:
        ensure => 'running',
    }
}
