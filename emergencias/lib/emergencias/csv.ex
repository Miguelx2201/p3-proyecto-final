defmodule Emergencias.CSV do
  @moduledoc """
  Lectura y escritura genérica de archivos CSV (texto plano separado por `;`).

  Ninguna función lanza excepciones: devuelven `:ok`, `{:ok, datos}` o
  `{:error, razon}`.

  Cada entidad aporta dos funciones que se pasan como argumento:

    * `to_linea`: recibe la entidad y devuelve su línea de texto (sin salto de línea).
    * `de_linea`: recibe una línea de texto y devuelve `{:ok, entidad}` o
      `{:error, razon}`. **Debe devolver una tupla de error ante una línea
      corrupta** (por ejemplo, con una cláusula final que acepte cualquier valor),
      porque este módulo no captura excepciones.
  """

  @separador ";"

  @doc """
  Ruta de un archivo dentro de la carpeta de datos.

  La carpeta sale de `config :emergencias, :data_dir` y por defecto es `data`.
  """
  def ruta(nombre) do
    Path.join(Application.get_env(:emergencias, :data_dir, "data"), nombre)
  end

  @doc """
  Escribe el archivo completo: cabecera y una línea por entidad.

  Crea la carpeta si no existe. Escribe primero a un archivo temporal y luego lo
  renombra, así una falla a mitad de la escritura no deja el archivo a medias.
  """
  def escribir(ruta, cabecera, entidades, to_linea) do
    contenido =
      cabecera <> "\n" <> Enum.map_join(entidades, fn entidad -> to_linea.(entidad) <> "\n" end)

    temporal = ruta <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(ruta)),
         :ok <- File.write(temporal, contenido),
         :ok <- File.rename(temporal, ruta) do
      :ok
    else
      {:error, razon} ->
        File.rm(temporal)
        {:error, razon}
    end
  end

  @doc """
  Agrega una línea al final del archivo (para historiales).

  Si el archivo no existe lo crea con la cabecera.
  """
  def agregar(ruta, cabecera, entidad, to_linea) do
    with :ok <- File.mkdir_p(Path.dirname(ruta)),
         :ok <- asegurar_cabecera(ruta, cabecera),
         :ok <- File.write(ruta, to_linea.(entidad) <> "\n", [:append]) do
      :ok
    end
  end

  defp asegurar_cabecera(ruta, cabecera) do
    if File.exists?(ruta), do: :ok, else: File.write(ruta, cabecera <> "\n")
  end

  @doc """
  Lee el archivo y convierte cada línea de datos con `de_linea`.

    * Archivo inexistente: `{:ok, []}`.
    * Línea corrupta: `{:error, {:linea_invalida, n}}`, donde `n` es el número
      de línea dentro del archivo (la cabecera es la línea 1).
    * Otro problema de lectura: `{:error, razon}`.

  Acepta saltos de línea de Windows (`\\r\\n`) y ignora las líneas vacías.
  """
  def leer(ruta, de_linea) do
    case File.read(ruta) do
      {:ok, contenido} ->
        case numerar_lineas(contenido) do
          [] -> {:ok, []}
          [_cabecera | datos] -> parsear_lineas(datos, de_linea, [])
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, razon} ->
        {:error, razon}
    end
  end

  defp numerar_lineas(contenido) do
    contenido
    |> String.split(["\r\n", "\n"])
    |> Enum.with_index(1)
    |> Enum.map(fn {linea, n} -> {String.trim(linea), n} end)
    |> Enum.reject(fn {linea, _n} -> linea == "" end)
  end

  # Recursiva con acumulador (de cola): se detiene en la primera línea inválida.
  defp parsear_lineas([], _de_linea, acumulado), do: {:ok, Enum.reverse(acumulado)}

  defp parsear_lineas([{linea, n} | resto], de_linea, acumulado) do
    case de_linea.(linea) do
      {:ok, entidad} -> parsear_lineas(resto, de_linea, [entidad | acumulado])
      _ -> {:error, {:linea_invalida, n}}
    end
  end

  @doc """
  Divide una línea en sus campos.

      iex> Emergencias.CSV.separar("R001;agua;50")
      ["R001", "agua", "50"]
  """
  def separar(linea), do: String.split(linea, @separador)

  @doc """
  Une campos en una línea. Los textos libres deben sanitizarse antes con
  `Emergencias.Util.sanitizar_texto/1` para que no contengan `;`.

      iex> Emergencias.CSV.unir(["R001", "agua", 50])
      "R001;agua;50"
  """
  def unir(campos), do: Enum.join(campos, @separador)
end
