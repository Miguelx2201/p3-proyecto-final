import Config

# Carpeta donde la aplicación guarda los archivos CSV.
config :emergencias, :data_dir, "data"

# En pruebas se usa otra carpeta para no tocar los datos reales.
if config_env() == :test do
  import_config "test.exs"
end
