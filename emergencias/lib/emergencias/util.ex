defmodule Emergencias.Util do
  @moduledoc """
  Funciones compartidas de consola y de conversión de texto.

  Ninguna función de este módulo lanza excepciones: las conversiones devuelven
  `{:ok, valor}` o `{:error, razon}`.
  """

  @tipos_entrada [:texto, :entero, :real, :boolean]

  # ---------------------------------------------------------------------------
  # Entrada y salida
  # ---------------------------------------------------------------------------

  @doc """
  Imprime un mensaje seguido de un salto de línea.
  """
  def mostrar_mensaje(texto), do: IO.puts(texto)

  @doc """
  Pide un dato por consola y lo devuelve ya convertido.

  `tipo` puede ser `:texto`, `:entero`, `:real` o `:boolean` (acepta `si` o `no`).
  Si el dato es inválido muestra el motivo y vuelve a pedirlo (recursión).

  Devuelve `{:ok, valor}`, o `{:error, :eof}` si la entrada se cierra, o
  `{:error, :tipo_invalido}` si `tipo` no es uno de los cuatro permitidos.
  """
  def ingresar(mensaje, tipo) when tipo in @tipos_entrada do
    case IO.gets(mensaje <> " ") do
      :eof ->
        {:error, :eof}

      {:error, _razon} ->
        {:error, :eof}

      linea ->
        case convertir(linea, tipo) do
          {:ok, valor} ->
            {:ok, valor}

          {:error, razon} ->
            mostrar_mensaje("Dato inválido (#{razon}). Intente de nuevo.")
            ingresar(mensaje, tipo)
        end
    end
  end

  def ingresar(_mensaje, _tipo), do: {:error, :tipo_invalido}

  defp convertir(linea, :texto) do
    if vacio?(linea), do: {:error, :texto_vacio}, else: {:ok, sanitizar_texto(linea)}
  end

  defp convertir(linea, :entero), do: parsear_entero(linea)
  defp convertir(linea, :real), do: parsear_real(linea)

  defp convertir(linea, :boolean) do
    case linea |> String.trim() |> String.downcase() do
      respuesta when respuesta in ["si", "sí"] -> {:ok, true}
      "no" -> {:ok, false}
      _ -> {:error, :booleano_invalido}
    end
  end

  # ---------------------------------------------------------------------------
  # Conversión segura de texto
  # ---------------------------------------------------------------------------

  @doc """
  Convierte texto a entero. Rechaza texto con basura como `12a` o `3.5`.

      iex> Emergencias.Util.parsear_entero("42")
      {:ok, 42}
      iex> Emergencias.Util.parsear_entero(" -3 ")
      {:ok, -3}
      iex> Emergencias.Util.parsear_entero("12a")
      {:error, :entero_invalido}
  """
  def parsear_entero(texto) when is_binary(texto) do
    case Integer.parse(String.trim(texto)) do
      {numero, ""} -> {:ok, numero}
      _ -> {:error, :entero_invalido}
    end
  end

  def parsear_entero(_otro), do: {:error, :entero_invalido}

  @doc """
  Como `parsear_entero/1`, pero también rechaza los negativos.

      iex> Emergencias.Util.parsear_entero_no_negativo("0")
      {:ok, 0}
      iex> Emergencias.Util.parsear_entero_no_negativo("-3")
      {:error, :entero_invalido}
  """
  def parsear_entero_no_negativo(texto) do
    case parsear_entero(texto) do
      {:ok, numero} when numero >= 0 -> {:ok, numero}
      _ -> {:error, :entero_invalido}
    end
  end

  @doc """
  Convierte texto a número decimal (acepta enteros como `3`, que dan `3.0`).

      iex> Emergencias.Util.parsear_real("3.5")
      {:ok, 3.5}
      iex> Emergencias.Util.parsear_real("3")
      {:ok, 3.0}
      iex> Emergencias.Util.parsear_real("abc")
      {:error, :real_invalido}
  """
  def parsear_real(texto) when is_binary(texto) do
    case Float.parse(String.trim(texto)) do
      {numero, ""} -> {:ok, numero}
      _ -> {:error, :real_invalido}
    end
  end

  def parsear_real(_otro), do: {:error, :real_invalido}

  @doc """
  Convierte texto a uno de los átomos `permitidos`, sin distinguir mayúsculas
  ni espacios alrededor.

  Nunca usa `String.to_atom/1`: busca entre los átomos permitidos, así el texto
  del usuario no puede crear átomos nuevos.

      iex> Emergencias.Util.parsear_enum("AGUA ", [:agua, :alimentos])
      {:ok, :agua}
      iex> Emergencias.Util.parsear_enum("hack", [:agua, :alimentos])
      {:error, :valor_invalido}
  """
  def parsear_enum(texto, permitidos) when is_binary(texto) and is_list(permitidos) do
    normalizado = texto |> String.trim() |> String.downcase()

    case Enum.find(permitidos, fn atomo -> Atom.to_string(atomo) == normalizado end) do
      nil -> {:error, :valor_invalido}
      atomo -> {:ok, atomo}
    end
  end

  def parsear_enum(_texto, _permitidos), do: {:error, :valor_invalido}

  @doc """
  Prepara un texto libre para guardarlo en CSV: reemplaza `;` y los saltos de
  línea por un espacio y quita los espacios de los extremos. `nil` da `""`.

      iex> Emergencias.Util.sanitizar_texto("  Agua; urgente\\n  ")
      "Agua  urgente"
      iex> Emergencias.Util.sanitizar_texto(nil)
      ""
  """
  def sanitizar_texto(texto) when is_binary(texto) do
    texto
    |> String.replace([";", "\r\n", "\n", "\r"], " ")
    |> String.trim()
  end

  def sanitizar_texto(_otro), do: ""

  @doc """
  Fecha y hora actuales (UTC) en formato ISO 8601.
  """
  def ahora, do: DateTime.utc_now() |> DateTime.to_iso8601()

  @doc """
  Verdadero si el valor es `nil` o un texto con solo espacios.

      iex> Emergencias.Util.vacio?("   ")
      true
      iex> Emergencias.Util.vacio?(nil)
      true
      iex> Emergencias.Util.vacio?("agua")
      false
  """
  def vacio?(nil), do: true
  def vacio?(texto) when is_binary(texto), do: String.trim(texto) == ""
  def vacio?(_otro), do: false
end
