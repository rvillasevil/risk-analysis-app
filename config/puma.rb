# config/puma.rb

# Número de hilos
threads_count = Integer(ENV['RAILS_MAX_THREADS'] || 5)
threads threads_count, threads_count

# Puerto
port ENV.fetch('PORT', 3000)

# Entorno (usamos RAILS_ENV en lugar de RACK_ENV)
env = ENV.fetch('RAILS_ENV', 'development')
environment env

# Solo en producción activamos workers y preload_app
if env == 'production'
  workers Integer(ENV['WEB_CONCURRENCY'] || 2)
  preload_app!

  on_worker_boot do
    ActiveRecord::Base.establish_connection
  end
else
  # En dev/test no usamos workers (evita el error en Windows)
  workers 0
end

# Soporte IPv6
bind "tcp://[::]:#{ENV.fetch('PORT', 3000)}"

# Ajuste para Router 2.0 de Heroku
enable_keep_alives(false) if respond_to?(:enable_keep_alives)

