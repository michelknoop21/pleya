# Local command routing only; preserve Ruby, argv, cwd and the caller environment.
require 'rbconfig'

pleya_cli = '/Users/michelknoop/bin/pleya-heavy'
pleya_probe = '/Users/michelknoop/bin/pleya-heavy-route'
system('python3', pleya_probe, 'fastlane', *ARGV)
pleya_status = $?.exitstatus
if pleya_status == 10
  if ENV['PLEYA_HEAVY_QUEUE_FDS']
    system(pleya_cli, 'scope')
    pleya_status = $?.exitstatus
  end
  if pleya_status == 10
    exec(pleya_cli, 'run', '--label', 'route-fastlane', '--', RbConfig.ruby, $PROGRAM_NAME, *ARGV)
  elsif pleya_status != 0
    exit(pleya_status)
  end
elsif pleya_status != 0
  exit(pleya_status)
end
