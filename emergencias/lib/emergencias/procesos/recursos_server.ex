defmodule Emergencias.Procesos.RecursosServer do
  @moduledoc """
  Proceso dueño del inventario de recursos.

  Todo el inventario vive en un solo GenServer. Cada `handle_call` termina
  completo antes de empezar el siguiente, así que leer el stock, decidir y
  escribir es una operación atómica: dos reservas simultáneas nunca pueden
  superar el stock disponible.

  Estado: `%{recursos: %{id => Recurso}, movimientos: [Movimiento], contador_mov: n}`.
  `movimientos` guarda el más reciente primero; `historial/2` los devuelve del
  más antiguo al más reciente.

  Cada cambio reescribe `recursos.csv` y agrega los movimientos nuevos a
  `movimientos.csv`. Si guardar falla, la operación devuelve `{:error, razon}` y
  el estado en memoria no cambia.

  Ninguna función lanza excepciones: devuelven `{:ok, valor}` o
  `{:error, razon}`. Si el servidor no está en ejecución, la razón es
  `:servidor_no_disponible`.

  Todas las funciones reciben al final un argumento opcional `servidor`
  (por defecto el nombre `#{inspect(__MODULE__)}`), útil para pruebas.
  """

  use GenServer

  alias Emergencias.CSV
  alias Emergencias.Dominio.Movimiento
  alias Emergencias.Dominio.Recurso
  alias Emergencias.Persistencia
  alias Emergencias.Servicios.AsignacionServicio
  alias Emergencias.Servicios.ReportesServicio
  alias Emergencias.Util

  @archivo_movimientos "movimientos.csv"
  @referencia_devolucion "devolucion"
  @filtros [:categoria, :zona, :ubicacion]

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  @doc """
  Inicia el servidor y carga `recursos.csv` y `movimientos.csv`.

  Opción `:name` (por defecto el nombre del módulo). Si un archivo está
  corrupto devuelve `{:error, razon}`.
  """
  def start_link(opciones \\ []) do
    nombre = Keyword.get(opciones, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: nombre)
  end

  @doc """
  Registra un recurso nuevo. No crea ningún movimiento.

  Devuelve `{:ok, recurso}`. Errores: `:id_duplicado` y los de
  `Recurso.crear/7` (`:texto_vacio`, `:categoria_invalida`, `:cantidad_invalida`).
  """
  def registrar(
        id,
        nombre,
        categoria,
        cantidad,
        unidad,
        ubicacion,
        zona,
        servidor \\ __MODULE__
      ) do
    with {:ok, recurso} <-
           Recurso.crear(id, nombre, categoria, cantidad, unidad, ubicacion, zona) do
      llamar(servidor, {:registrar, recurso})
    end
  end

  @doc """
  Suma `cantidad` al recurso `id` y guarda un movimiento `:entrada`.

  Devuelve `{:ok, %{recurso: recurso, movimiento: movimiento}}`. Errores:
  `:recurso_no_encontrado`, `:cantidad_invalida`, `:texto_vacio` (usuario vacío).
  """
  def entrada(id, cantidad, usuario, servidor \\ __MODULE__) do
    llamar(servidor, {:entrada, id, cantidad, usuario})
  end

  @doc """
  Resta `cantidad` al recurso `id` y guarda un movimiento `:salida`.

  Devuelve `{:ok, %{recurso: recurso, movimiento: movimiento}}`. Errores:
  `:recurso_no_encontrado`, `:cantidad_invalida`, `:sin_stock`, `:texto_vacio`.
  """
  def salida(id, cantidad, usuario, servidor \\ __MODULE__) do
    llamar(servidor, {:salida, id, cantidad, usuario})
  end

  @doc """
  Reserva `cantidad` de la `categoria` en la `zona` para la necesidad
  `necesidad_id`, tomándola de los recursos en orden de `id`.

  Devuelve `{:ok, %{movimientos: [movimiento]}}` (movimientos `:asignacion` ya
  con `id`). Errores: los de `AsignacionServicio.reservar/5`
  (`:cantidad_invalida`, `:sin_stock`, `:texto_vacio`). Es todo o nada.
  """
  def reservar(categoria, zona, cantidad, necesidad_id, usuario, servidor \\ __MODULE__) do
    llamar(servidor, {:reservar, categoria, zona, cantidad, necesidad_id, usuario})
  end

  @doc """
  Compensación: revierte una reserva. Recibe los movimientos que devolvió
  `reservar/6`, suma de vuelta cada cantidad y registra un movimiento
  `:entrada` con referencia `"devolucion"`.

  Devuelve `{:ok, %{movimientos: [movimiento]}}` con las entradas creadas.
  Errores: `:movimientos_invalidos` (no es una lista de movimientos con `id`, o
  hay ids repetidos) y `:movimiento_desconocido` (alguno no es una asignación
  guardada por este servidor). Es todo o nada.

  Importante: el servidor no recuerda qué reservas ya fueron devueltas;
  evitar devolver dos veces la misma reserva es responsabilidad de quien llama.
  """
  def devolver(movimientos, servidor \\ __MODULE__) do
    llamar(servidor, {:devolver, movimientos})
  end

  @doc """
  Transfiere `cantidad` del recurso `id_origen` al centro `centro_destino`.

  El destino es el recurso (distinto del origen) de la misma categoría, unidad
  y zona cuya `ubicacion` es `centro_destino`; si no existe, se crea uno nuevo
  (ver `AsignacionServicio.transferir/5`).

  Devuelve `{:ok, %{origen: origen, destino: destino, movimientos: [salida, entrada]}}`.
  Errores: `:recurso_no_encontrado`, `:id_duplicado` (el id del destino nuevo ya
  existe) y los de `AsignacionServicio.transferir/5`.
  """
  def transferir(id_origen, centro_destino, cantidad, usuario, servidor \\ __MODULE__) do
    llamar(servidor, {:transferir, id_origen, centro_destino, cantidad, usuario})
  end

  @doc "Suma disponible de la `categoria` en la `zona`. Devuelve `{:ok, entero}`."
  def disponibilidad(categoria, zona, servidor \\ __MODULE__) do
    llamar(servidor, {:disponibilidad, categoria, zona})
  end

  @doc """
  Lista los recursos ordenados por `id`.

  `filtros` es una lista de pares o un mapa con las claves `:categoria`, `:zona`
  y/o `:ubicacion` (comparación exacta). Otra cosa da `{:error, :filtro_invalido}`.
  """
  def listar(filtros \\ [], servidor \\ __MODULE__) do
    llamar(servidor, {:listar, filtros})
  end

  @doc """
  Movimientos del recurso `id`, del más antiguo al más reciente.
  Error: `:recurso_no_encontrado`.
  """
  def historial(id, servidor \\ __MODULE__) do
    llamar(servidor, {:historial, id})
  end

  @doc "Devuelve `{:ok, recurso}` o `{:error, :recurso_no_encontrado}`."
  def obtener(id, servidor \\ __MODULE__) do
    llamar(servidor, {:obtener, id})
  end

  defp llamar(servidor, mensaje) do
    GenServer.call(servidor, mensaje)
  catch
    :exit, _razon -> {:error, :servidor_no_disponible}
  end

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    with {:ok, recursos} <- Persistencia.cargar_recursos(),
         {:ok, movimientos} <- cargar_movimientos() do
      {:ok,
       %{
         recursos: Map.new(recursos, fn recurso -> {recurso.id, recurso} end),
         movimientos: Enum.reverse(movimientos),
         contador_mov: ultimo_contador(movimientos)
       }}
    else
      {:error, razon} -> {:stop, razon}
    end
  end

  @impl true
  def handle_call(mensaje, _from, estado) do
    case ejecutar(mensaje, estado) do
      {:ok, respuesta, nuevo_estado} -> {:reply, {:ok, respuesta}, nuevo_estado}
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  # Cada operación devuelve `{:ok, respuesta, estado_nuevo}` o `{:error, razon}`.
  # Si devuelve error, `handle_call/3` conserva el estado anterior.
  defp ejecutar({:registrar, %Recurso{} = recurso}, estado) do
    with :ok <- validar_id_libre(estado, recurso.id),
         {:ok, nuevo, _movimientos} <- aplicar(estado, [recurso], []) do
      {:ok, recurso, nuevo}
    end
  end

  defp ejecutar({tipo, id, cantidad, usuario}, estado) when tipo in [:entrada, :salida] do
    with {:ok, recurso} <- buscar(estado, id),
         {:ok, actualizado} <- cambiar_stock(tipo, recurso, cantidad),
         {:ok, movimiento} <- Movimiento.nuevo(recurso.id, tipo, cantidad, usuario, nil),
         {:ok, nuevo, [guardado]} <- aplicar(estado, [actualizado], [movimiento]) do
      {:ok, %{recurso: actualizado, movimiento: guardado}, nuevo}
    end
  end

  defp ejecutar({:reservar, categoria, zona, cantidad, necesidad_id, usuario}, estado) do
    candidatos = recursos_de(estado, &(&1.categoria == categoria and &1.zona == zona))

    with {:ok, %{recursos: recursos, movimientos: movimientos}} <-
           AsignacionServicio.reservar(candidatos, categoria, cantidad, necesidad_id, usuario),
         {:ok, nuevo, guardados} <- aplicar(estado, recursos, movimientos) do
      {:ok, %{movimientos: guardados}, nuevo}
    end
  end

  defp ejecutar({:devolver, []}, estado), do: {:ok, %{movimientos: []}, estado}

  defp ejecutar({:devolver, movimientos}, estado) when is_list(movimientos) do
    with {:ok, originales} <- localizar_asignaciones(estado, movimientos),
         {:ok, recursos, entradas} <- revertir(originales, estado, %{}, []),
         {:ok, nuevo, guardados} <- aplicar(estado, recursos, entradas) do
      {:ok, %{movimientos: guardados}, nuevo}
    end
  end

  defp ejecutar({:devolver, _otro}, _estado), do: {:error, :movimientos_invalidos}

  defp ejecutar({:transferir, id_origen, centro_destino, cantidad, usuario}, estado) do
    centro = Util.sanitizar_texto(centro_destino)

    with {:ok, origen} <- buscar(estado, id_origen),
         destino = buscar_destino(estado, origen, centro),
         {:ok, resultado} <-
           AsignacionServicio.transferir(origen, destino, cantidad, centro_destino, usuario),
         :ok <- validar_destino_libre(estado, destino, resultado.destino),
         {:ok, nuevo, guardados} <-
           aplicar(estado, [resultado.origen, resultado.destino], resultado.movimientos) do
      {:ok, %{resultado | movimientos: guardados}, nuevo}
    end
  end

  defp ejecutar({:disponibilidad, categoria, zona}, estado) do
    total = ReportesServicio.disponibilidad(Map.values(estado.recursos), categoria, zona)
    {:ok, total, estado}
  end

  defp ejecutar({:listar, filtros}, estado) do
    with {:ok, pares} <- normalizar_filtros(filtros) do
      lista = recursos_de(estado, fn recurso -> Enum.all?(pares, &coincide?(recurso, &1)) end)
      {:ok, lista, estado}
    end
  end

  defp ejecutar({:historial, id}, estado) do
    with {:ok, recurso} <- buscar(estado, id) do
      historial =
        estado.movimientos
        |> Enum.filter(&(&1.recurso_id == recurso.id))
        |> Enum.reverse()

      {:ok, historial, estado}
    end
  end

  defp ejecutar({:obtener, id}, estado) do
    with {:ok, recurso} <- buscar(estado, id), do: {:ok, recurso, estado}
  end

  defp ejecutar(_mensaje, _estado), do: {:error, :mensaje_invalido}

  # ---------------------------------------------------------------------------
  # Ayudas del estado
  # ---------------------------------------------------------------------------

  defp buscar(estado, id) do
    case Map.fetch(estado.recursos, id) do
      {:ok, recurso} -> {:ok, recurso}
      :error -> {:error, :recurso_no_encontrado}
    end
  end

  defp validar_id_libre(estado, id) do
    if Map.has_key?(estado.recursos, id), do: {:error, :id_duplicado}, else: :ok
  end

  defp cambiar_stock(:entrada, recurso, cantidad), do: Recurso.entrada(recurso, cantidad)
  defp cambiar_stock(:salida, recurso, cantidad), do: Recurso.salida(recurso, cantidad)

  # Recursos que cumplen `filtro`, ordenados por id para que el resultado sea
  # siempre el mismo.
  defp recursos_de(estado, filtro) do
    estado.recursos
    |> Map.values()
    |> Enum.sort_by(& &1.id)
    |> Enum.filter(filtro)
  end

  defp buscar_destino(estado, origen, centro) do
    estado
    |> recursos_de(&destino_compatible?(&1, origen, centro))
    |> List.first()
  end

  defp destino_compatible?(recurso, origen, centro) do
    recurso.id != origen.id and recurso.categoria == origen.categoria and
      recurso.unidad == origen.unidad and recurso.zona == origen.zona and
      recurso.ubicacion == centro
  end

  # Si el destino se creó nuevo, su id no debe pisar a otro recurso existente.
  defp validar_destino_libre(estado, nil, destino), do: validar_id_libre(estado, destino.id)
  defp validar_destino_libre(_estado, _existente, _destino), do: :ok

  defp normalizar_filtros(filtros) when is_map(filtros) do
    normalizar_filtros(Map.to_list(filtros))
  end

  defp normalizar_filtros(filtros) when is_list(filtros) do
    if Enum.all?(filtros, &match?({campo, _valor} when campo in @filtros, &1)) do
      {:ok, filtros}
    else
      {:error, :filtro_invalido}
    end
  end

  defp normalizar_filtros(_otro), do: {:error, :filtro_invalido}

  defp coincide?(recurso, {campo, valor}), do: Map.get(recurso, campo) == valor

  # ---------------------------------------------------------------------------
  # Devolución
  # ---------------------------------------------------------------------------

  # Cada movimiento debe ser una asignación que este servidor guardó (se busca
  # por id en su historial); así no se puede devolver algo inventado.
  defp localizar_asignaciones(estado, movimientos) do
    ids = for %Movimiento{id: id} when is_binary(id) <- movimientos, do: id

    cond do
      length(ids) != length(movimientos) -> {:error, :movimientos_invalidos}
      length(Enum.uniq(ids)) != length(ids) -> {:error, :movimientos_invalidos}
      true -> buscar_asignaciones(estado, ids)
    end
  end

  defp buscar_asignaciones(estado, ids) do
    por_id = Map.new(estado.movimientos, fn movimiento -> {movimiento.id, movimiento} end)
    originales = Enum.map(ids, &Map.get(por_id, &1))

    if Enum.any?(originales, &(is_nil(&1) or &1.tipo != :asignacion)) do
      {:error, :movimiento_desconocido}
    else
      {:ok, originales}
    end
  end

  # Recorre las asignaciones acumulando los recursos ya actualizados y las
  # entradas nuevas (en orden inverso). Nada se guarda hasta que todas pasan.
  defp revertir([], _estado, recursos, entradas) do
    {:ok, Map.values(recursos), Enum.reverse(entradas)}
  end

  defp revertir([original | resto], estado, recursos, entradas) do
    with {:ok, recurso} <- recurso_vigente(original.recurso_id, estado, recursos),
         {:ok, actualizado, entrada} <- devolver_uno(recurso, original) do
      recursos = Map.put(recursos, actualizado.id, actualizado)
      revertir(resto, estado, recursos, [entrada | entradas])
    end
  end

  defp recurso_vigente(id, estado, recursos) do
    case Map.fetch(recursos, id) do
      {:ok, recurso} -> {:ok, recurso}
      :error -> buscar(estado, id)
    end
  end

  defp devolver_uno(recurso, %{recurso_id: id, cantidad: cantidad, usuario: usuario}) do
    with {:ok, actualizado} <- Recurso.entrada(recurso, cantidad),
         {:ok, entrada} <-
           Movimiento.nuevo(id, :entrada, cantidad, usuario, @referencia_devolucion) do
      {:ok, actualizado, entrada}
    end
  end

  # ---------------------------------------------------------------------------
  # Aplicar y guardar
  # ---------------------------------------------------------------------------

  # Aplica los cambios al estado, asigna ids a los movimientos y guarda en
  # disco. Devuelve el estado nuevo solo si se pudo guardar.
  defp aplicar(estado, cambiados, movimientos) do
    {guardados, contador} =
      Enum.map_reduce(movimientos, estado.contador_mov, fn movimiento, n ->
        {%{movimiento | id: formatear_id(n + 1)}, n + 1}
      end)

    nuevo = %{
      estado
      | recursos: Enum.reduce(cambiados, estado.recursos, &Map.put(&2, &1.id, &1)),
        movimientos: Enum.reverse(guardados, estado.movimientos),
        contador_mov: contador
    }

    with :ok <- persistir(estado, nuevo, guardados), do: {:ok, nuevo, guardados}
  end

  defp persistir(anterior, nuevo, movimientos) do
    with :ok <- Persistencia.guardar_recursos(lista_de_recursos(nuevo)),
         :ok <- agregar_movimientos(movimientos) do
      :ok
    else
      {:error, razon} ->
        # Mejor esfuerzo: dejar recursos.csv como estaba antes de la operación.
        _ = Persistencia.guardar_recursos(lista_de_recursos(anterior))
        {:error, razon}
    end
  end

  defp lista_de_recursos(estado) do
    estado.recursos
    |> Map.values()
    |> Enum.sort_by(& &1.id)
  end

  defp agregar_movimientos([]), do: :ok

  defp agregar_movimientos([movimiento | resto]) do
    with :ok <- Persistencia.agregar_movimiento(movimiento), do: agregar_movimientos(resto)
  end

  # ---------------------------------------------------------------------------
  # Ids de movimientos y carga inicial
  # ---------------------------------------------------------------------------

  defp formatear_id(numero), do: "MV" <> String.pad_leading(Integer.to_string(numero), 3, "0")

  defp cargar_movimientos do
    CSV.leer(CSV.ruta(@archivo_movimientos), &Movimiento.de_linea/1)
  end

  # El contador sigue desde el id numérico más alto ya guardado ("MV007" -> 7).
  defp ultimo_contador(movimientos) do
    Enum.reduce(movimientos, 0, fn movimiento, mayor ->
      max(mayor, numero_de_id(movimiento.id))
    end)
  end

  defp numero_de_id(id) do
    case Regex.run(~r/^MV(\d+)$/, id) do
      [_todo, digitos] -> String.to_integer(digitos)
      nil -> 0
    end
  end
end
