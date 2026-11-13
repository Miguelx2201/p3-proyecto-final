# Cada ejecución de pruebas empieza con la carpeta de datos de prueba vacía.
# Solo se borra si está dentro de tmp/, para no tocar nunca datos reales.
datos = Application.get_env(:emergencias, :data_dir)

if is_binary(datos) and String.starts_with?(datos, "tmp/") do
  File.rm_rf(datos)
  File.mkdir_p(datos)
end

ExUnit.start()
