# TODO: Verbose flag
def log(str)
  puts str
end

# Create the initialize function call with arguments
def initialize_args(items)
  sig = "\"initialize(#{items.map(&:first).join(',')})\""
  args = cast_norms(*items.map(&:last)).join(' ')

  cmd = "cast calldata #{sig} #{args}"
  log "Initializer data: #{cmd}"
  `#{cmd}`.strip
end

def cast_norm(value)
  if value.kind_of?(String)
    "\"#{value}\""
  elsif value.kind_of?(Float)
    value.to_i
  else
    value
  end
end

def cast_norms(*args)
  args.map { |v| cast_norm(v) }
end

def transfer_tokens(token_addr, to_addr, amount, private_key)
  system "cast send #{token_addr} \"transfer(address,uint256)\" #{to_addr} #{amount} --private-key #{private_key}"
end

def deploy(name, private_key, *constructor_args)
  cmd = "forge create #{name} --private-key #{private_key}"

  unless constructor_args.empty?
    flat = cast_norms(*constructor_args.map).join(' ')
    cmd << " --constructor-args #{flat}"
  end

  log "Executing: #{cmd}"
  capture = `#{cmd}`
  abort(capture) if $? != 0

  capture =~ /Deployed to: (\w+)/
  address = $1
  log "Deployed #{name}: #{address}"

  address
end