node default {
   # Project settings
   $mezzanine_project_parent_dir="/home/sanoma"
   $mezzanine_project_name="emptyproject"
   $mezzanine_project_user="sanoma"


   user { "${mezzanine_project_user}-user":
      name => "${mezzanine_project_user}",
      password => '$6$N4.4WYqG$en9xJqudHKvhsvVBdgJkuVs4r3NshJEQ1if1Ej/9gC2IRP2kKSvCqUuIxWtrz4KfGOHeIEP4S9.lGY4IhtSUY/',
      managehome => true,
      ensure => present
   }

   package { 'epel-release-6-8':
      source => 'http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm',
      ensure => installed
   }


   package { 'python-pip':
      ensure => installed,
      require => Package['epel-release-6-8']
   }

   package { 'python-devel':
      ensure => installed,
      require => Package['epel-release-6-8']
   }
 
   python::pip { 'gunicorn':
      pkgname => 'gunicorn'
   }

   python::pip { 'mezzanine':
      pkgname => 'mezzanine',
      require => Package['python-devel']
   }

   package { 'nginx':
      ensure => installed
   }

   # Setup project
   exec { "setupproject_$mezzanine_project_name":
      path => "/sbin:/bin:/usr/bin",
      onlyif => "test ! -f $mezzanine_project_parent_dir/$mezzanine_project_name/local_settings.py",
      command => "su -c \"cd $mezzanine_project_parent_dir;mezzanine-project $mezzanine_project_name\" $mezzanine_project_user",
      require => [ Python::Pip['mezzanine'] , User["${mezzanine_project_user}-user"] ]
   }

   # Append required settings to local_settings.py file. 
   # TODO: - Can only append and not change existing settings
   #       - If possible use tool like Augeas for adjusting existing config files.
   exec { "add_allowed_hosts_$mezzanine_project_name":
      path => "/sbin:/bin:/usr/bin",
      onlyif =>  "test `grep ^ALLOWED_HOSTS $mezzanine_project_parent_dir/$mezzanine_project_name/local_settings.py|grep localhost|wc -l` -eq 0",
      command => "echo 'ALLOWED_HOSTS = \"localhost\"' >> $mezzanine_project_parent_dir/$mezzanine_project_name/local_settings.py",
      require => Exec["setupproject_$mezzanine_project_name"]
   }

   exec { "add_time_zone_$mezzanine_project_name":
      path => "/sbin:/bin:/usr/bin",
      onlyif =>  "test `grep ^TIME_ZONE $mezzanine_project_parent_dir/$mezzanine_project_name/local_settings.py|grep 'Europe/Amsterdam'|wc -l` -eq 0",
      command => "echo 'TIME_ZONE = \"Europe/Amsterdam\"' >> $mezzanine_project_parent_dir/$mezzanine_project_name/local_settings.py",
      require => Exec["setupproject_$mezzanine_project_name"]
   }

     
   # Initialize DB if not already exists
   exec { "create_mezzanine_db_$mezzanine_project_name":
      path => "/sbin:/bin:/usr/bin",
      onlyif => "test ! -f $mezzanine_project_parent_dir/$mezzanine_project_name/dev.db",
      command => "su -c \"cd $mezzanine_project_parent_dir/$mezzanine_project_name;python manage.py createdb --noinput\" $mezzanine_project_user",
      require => [ Exec["add_allowed_hosts_$mezzanine_project_name"], Exec["add_time_zone_$mezzanine_project_name"] ]
   }

   # Copy static content
   exec { "copy_static_content_$mezzanine_project_name":
      path => "/sbin:/bin:/usr/bin",
      onlyif => "test ! -f $mezzanine_project_parent_dir/$mezzanine_project_name/static/robots.txt",
      command => "su -c \"cd $mezzanine_project_parent_dir/$mezzanine_project_name;python manage.py collectstatic --noinput\" $mezzanine_project_user",
      require => [ Exec["setupproject_$mezzanine_project_name"] , File["/home/$mezzanine_project_user"] ]
   }


   file { "/etc/rc.d/init.d/gunicorn_django":
      ensure => present,
      owner => root,
      group => root,
      mode => 755,
      content => template("/vagrant/deploy/puppet/templates/gunicorn_django-initd.erb")
   }

   service { "nginx":
      ensure => running,
      enable => true,
      require => Package['nginx'],
      subscribe => [ File['/etc/nginx/conf.d/gunicorn_django.conf'],File['/etc/nginx/conf.d/default.conf'] ]

   }

   service { "gunicorn_django":
      ensure => running,
      enable => true,
      require => [ File['/etc/rc.d/init.d/gunicorn_django'], Python::Pip['gunicorn'] ],
      subscribe => File["$mezzanine_project_parent_dir/$mezzanine_project_name/gunicorn.conf.py"]
   }

   file { "$mezzanine_project_parent_dir/$mezzanine_project_name/gunicorn.conf.py":
      ensure => present,
      owner => $mezzanine_project_user,
      group => $mezzanine_project_user,
      mode => 644,
      content => template("/vagrant/deploy/puppet/templates/gunicorn.conf.py.erb"),
      require => Exec["setupproject_$mezzanine_project_name"]
   }

   file { "/etc/nginx/conf.d/gunicorn_django.conf":
      ensure => present,
      owner => root,
      group => root,
      mode => 644,
      content => template("/vagrant/deploy/puppet/templates/nginx-gunicorn.conf.erb"),
      require => Package['nginx']
   }

   file { "/etc/nginx/conf.d/default.conf":
      ensure => absent,
      require => Package['nginx']
   }

   # Open permissions on home directory sanoma user to enable nginx access to static content
   file { "/home/$mezzanine_project_user":
      ensure => directory,
      owner => $mezzanine_project_user,
      group => $mezzanine_project_user,
      mode => 755,
      require => User["${mezzanine_project_user}-user"]
   }
   
}


