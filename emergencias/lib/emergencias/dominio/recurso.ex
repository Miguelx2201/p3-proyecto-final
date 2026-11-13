defmodule Emergencias.Dominio.Recurso do
  @moduledoc """
  Recurso disponible en un centro de apoyo (agua, alimentos, medicamentos...).

  La entidad es inmutable: `entrada/2` y `salida/2` reciben la struct y devuelven
  una nueva. La cantidad disponible nunca puede quedar negativa.

  Ninguna función lanza excepciones: devuelven `{:ok, valor}` o `{:error, razon}`.
  """

  alias Emergencias.CSV
  alias Emergencias.Util

  @categorias [
    :agua,
    :alimentos,
    :medicamentos,
    :primeros_auxilios,
    :refugio,
    :transporte,
    :rescate,
    :otra
  ]

  @cabecera "id;nombre;categoria;cantidad;unidad;ubicacion;zona"

  @enforce_keys [:id, :nombre, :categoria, :cantidad_disponible, :unidad, :ubicacion, :zona]
  defstruct [:id, :nombre, :categoria, :cantidad_disponible, :unidad, :ubicacion, :zona]

  @type categoria ::
          :agua
          | :alimentos
          | :medicamentos
          | :primeros_auxilios
          | :refugio
          | :transporte
          | :rescate
          | :otra

  @type t :: %__MODULE__{
          id: String.t(),
          nombre: String.t(),
          categoria: categoria(),
          cantidad_disponible: non_neg_integer(),
          unidad: String.t(),
          ubicacion: String.t(),
          zona: String.t()
        }

  @doc "Categorías válidas de un recurso."
  def categorias, do: @categorias

  @doc "Cabecera del archivo `recursos.csv`."
  def cabecera, do: @cabecera

  @doc """
  Crea un recurso validando sus datos.

  Los textos (`id`, `nombre`, `unidad`, `ubicacion`, `zona`) se sanitizan y no
  pueden quedar vacíos. La `categoria` debe ser una de `categorias/0` y la
  `cantidad` un entero mayor o igual a 0.

  Errores: `:texto_vacio`, `:categoria_invalida`, `:cantidad_invalida`.
  """
  def crear(id, nombre, categoria, cantidad, unidad, ubicacion, zona) do
    with {:ok, id} <- validar_texto(id),
         {:ok, nombre} <- validar_texto(nombre),
         {:ok, unidad} <- validar_texto(unidad),
         {:ok, ubicacion} <- validar_texto(ubicacion),
         {:ok, zona} <- validar_texto(zona),
         {:ok, categoria} <- validar_categoria(categoria),
         {:ok, cantidad} <- validar_cantidad_inicial(cantidad) do
      {:ok,
       %__MODULE__{
         id: id,
         nombre: nombre,
         categoria: categoria,
         cantidad_disponible: cantidad,
         unidad: unidad,
         ubicacion: ubicacion,
         zona: zona
       }}
    end
  end

  @doc """
  Suma `cantidad` (entero mayor que 0) a la cantidad disponible.

  Error: `:cantidad_invalida`.
  """
  def entrada(%__MODULE__{} = recurso, cantidad) when is_integer(cantidad) and cantidad > 0 do
    {:ok, %{recurso | cantidad_disponible: recurso.cantidad_disponible + cantidad}}
  end

  def entrada(%__MODULE__{}, _cantidad), do: {:error, :cantidad_invalida}

  @doc """
  Resta `cantidad` (entero mayor que 0) de la cantidad disponible.

  Errores: `:cantidad_invalida`, y `:sin_stock` si `cantidad` supera lo disponible.
  """
  def salida(%__MODULE__{} = recurso, cantidad) when is_integer(cantidad) and cantidad > 0 do
    if cantidad > recurso.cantidad_disponible do
      {:error, :sin_stock}
    else
      {:ok, %{recurso | cantidad_disponible: recurso.cantidad_disponible - cantidad}}
    end
  end

  def salida(%__MODULE__{}, _cantidad), do: {:error, :cantidad_invalida}

  @doc """
  Convierte el recurso en una línea de `recursos.csv`
  (`id;nombre;categoria;cantidad;unidad;ubicacion;zona`).
  """
  def a_linea(%__MODULE__{} = recurso) do
    CSV.unir([
      Util.sanitizar_texto(recurso.id),
      Util.sanitizar_texto(recurso.nombre),
      recurso.categoria,
      recurso.cantidad_disponible,
      Util.sanitizar_texto(recurso.unidad),
      Util.sanitizar_texto(recurso.ubicacion),
      Util.sanitizar_texto(recurso.zona)
    ])
  end

  @doc """
  Convierte una línea de `recursos.csv` en un recurso.

  Devuelve `{:ok, recurso}` o `{:error, razon}`; una línea corrupta nunca lanza
  excepción.
  """
  def de_linea(linea) when is_binary(linea) do
    case CSV.separar(linea) do
      [id, nombre, categoria, cantidad, unidad, ubicacion, zona] ->
        with {:ok, categoria} <- Util.parsear_enum(categoria, @categorias),
             {:ok, cantidad} <- Util.parsear_entero_no_negativo(cantidad) do
          crear(id, nombre, categoria, cantidad, unidad, ubicacion, zona)
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

  defp validar_categoria(categoria) when categoria in @categorias, do: {:ok, categoria}
  defp validar_categoria(_otra), do: {:error, :categoria_invalida}

  defp validar_cantidad_inicial(cantidad) when is_integer(cantidad) and cantidad >= 0,
    do: {:ok, cantidad}

  defp validar_cantidad_inicial(_otra), do: {:error, :cantidad_invalida}
end
