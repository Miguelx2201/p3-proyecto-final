defmodule Emergencias.Dominio.Actividad do
  @moduledoc """
  Registro de un comando ejecutado por un usuario y de su resultado.

  `resultado` es un texto: `"ok"` o `"error:razon"`. Se guarda en `actividad.csv`
  (`fecha;usuario;comando;resultado`).

  Ninguna función lanza excepciones: devuelven `{:ok, valor}` o `{:error, razon}`.
  """

  alias Emergencias.CSV
  alias Emergencias.Util

  @archivo "actividad.csv"
  @cabecera "fecha;usuario;comando;resultado"

  @enforce_keys [:fecha, :usuario, :comando, :resultado]
  defstruct [:fecha, :usuario, :comando, :resultado]

  @type t :: %__MODULE__{
          fecha: String.t(),
          usuario: String.t(),
          comando: String.t(),
          resultado: String.t()
        }

  @doc "Nombre del archivo `actividad.csv`."
  def archivo, do: @archivo

  @doc "Cabecera del archivo `actividad.csv`."
  def cabecera, do: @cabecera

  @doc """
  Crea una actividad con la fecha actual.

  `resultado` puede ser `:ok`, `{:ok, valor}`, `{:error, razon}` (con `razon`
  átomo) o ya el texto `"ok"` / `"error:razon"`. Siempre se guarda como texto.

  Errores: `:texto_vacio` (usuario o comando vacíos) y `:resultado_invalido`.
  """
  def nuevo(usuario, comando, resultado) do
    with {:ok, usuario} <- validar_texto(usuario),
         {:ok, comando} <- validar_texto(comando),
         {:ok, resultado} <- normalizar_resultado(resultado) do
      {:ok,
       %__MODULE__{fecha: Util.ahora(), usuario: usuario, comando: comando, resultado: resultado}}
    end
  end

  @doc """
  Convierte la actividad en una línea de `actividad.csv`
  (`fecha;usuario;comando;resultado`).
  """
  def to_linea(%__MODULE__{} = actividad) do
    CSV.unir([
      Util.sanitizar_texto(actividad.fecha),
      Util.sanitizar_texto(actividad.usuario),
      Util.sanitizar_texto(actividad.comando),
      Util.sanitizar_texto(actividad.resultado)
    ])
  end

  @doc """
  Convierte una línea de `actividad.csv` en una actividad. Una línea corrupta
  devuelve `{:error, razon}` y nunca lanza excepción.
  """
  def de_linea(linea) when is_binary(linea) do
    case CSV.separar(linea) do
      [fecha, usuario, comando, resultado] ->
        with {:ok, fecha} <- validar_fecha(fecha),
             {:ok, usuario} <- validar_texto(usuario),
             {:ok, comando} <- validar_texto(comando),
             {:ok, resultado} <- validar_resultado(resultado) do
          {:ok,
           %__MODULE__{fecha: fecha, usuario: usuario, comando: comando, resultado: resultado}}
        end

      _ ->
        {:error, :linea_invalida}
    end
  end

  def de_linea(_otro), do: {:error, :linea_invalida}

  defp validar_texto(texto) do
    limpio = Util.sanitizar_texto(texto)
    if Util.vacio?(limpio), do: {:error, :texto_vacio}, else: {:ok, limpio}
  end

  defp normalizar_resultado(:ok), do: {:ok, "ok"}
  defp normalizar_resultado({:ok, _valor}), do: {:ok, "ok"}

  defp normalizar_resultado({:error, razon}) when is_atom(razon),
    do: {:ok, "error:" <> Atom.to_string(razon)}

  defp normalizar_resultado(texto) when is_binary(texto),
    do: validar_resultado(Util.sanitizar_texto(texto))

  defp normalizar_resultado(_otro), do: {:error, :resultado_invalido}

  defp validar_resultado("ok"), do: {:ok, "ok"}

  defp validar_resultado("error:" <> razon = texto) do
    if Util.vacio?(razon), do: {:error, :resultado_invalido}, else: {:ok, texto}
  end

  defp validar_resultado(_otro), do: {:error, :resultado_invalido}

  defp validar_fecha(fecha) do
    case DateTime.from_iso8601(fecha) do
      {:ok, _fecha, _desfase} -> {:ok, fecha}
      {:error, _razon} -> {:error, :fecha_invalida}
    end
  end
end
