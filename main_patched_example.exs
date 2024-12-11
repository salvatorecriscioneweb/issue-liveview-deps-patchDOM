Application.put_env(:sample, Example.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 5001],
  server: true,
  live_view: [signing_salt: "aaaaaaaa"],
  secret_key_base: String.duplicate("a", 64),
  # Need for make it works in NAT enviroment
  check_origin: false
)

Mix.install([
  {:plug_cowboy, "~> 2.5"},
  {:jason, "~> 1.0"},
  {:phoenix, "~> 1.7"},
  # please test your issue using the latest version of LV from GitHub!
  {:phoenix_live_view,
   github: "phoenixframework/phoenix_live_view", branch: "main", override: true}
])

# build the LiveView JavaScript assets (this needs mix and npm available in your path!)
path = Phoenix.LiveView.__info__(:compile)[:source] |> Path.dirname() |> Path.join("../")
System.cmd("mix", ["deps.get"], cd: path, into: IO.binstream())
System.cmd("npm", ["install"], cd: Path.join(path, "./assets"), into: IO.binstream())
System.cmd("mix", ["assets.build"], cd: path, into: IO.binstream())

defmodule Example.ErrorView do
  def render(template, _), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule Example.HomeLive do
  use Phoenix.LiveView, layout: {__MODULE__, :live}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :count, 0)}
  end

  def render("live.html", assigns) do
    ~H"""
    <script src="/assets/phoenix/phoenix.js"></script>
    <script src="/assets/phoenix_live_view/phoenix_live_view.js"></script>
    <script>
      /* Image we have a hook that stores the number of times a button is clicked
         We want to update the button's dataset when it's clicked
      Not using the assigns. */

      const myButtonHook = {
        mounted() {
          const that = this;
          this.el.dataset.timesClicked = 0;
          this.el.addEventListener("click", e => {
            // This not works for example
            that.el.dataset.timesClicked = (parseInt(that.el.dataset.timesClicked) || 0) + 1;
          });
        },
        updated() {
          console.log("Button updated", this.el.dataset.timesClicked); // This will give undefined because the dataset is removed in update
        },
      };
      let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
          hooks: {myButtonHook},
          dom: {
            onBeforeElUpdated(fromEl, toEl) {
              const isMyHook = fromEl.getAttribute("phx-hook") == "myButtonHook";
              if (isMyHook) {
                toEl.setAttribute("data-times-clicked", fromEl.getAttribute("data-times-clicked"));
              }
            }
          }
      })
      liveSocket.connect()
    </script>
    {@inner_content}
    """
  end

  def render(assigns) do
    ~H"""
    <div style="display: flex; gap: 4px;" >
    {@count}
    <button id="inc-button" phx-click="inc" phx-hook="myButtonHook">+</button>
    <button id="dec-button" phx-click="dec" phx-hook="myButtonHook">-</button>
    </div>
    """
  end

  def handle_event("inc", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count + 1)}
  end

  def handle_event("dec", _params, socket) do
    {:noreply, assign(socket, :count, socket.assigns.count - 1)}
  end
end

defmodule Example.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/", Example do
    pipe_through(:browser)

    live("/", HomeLive, :index)
  end
end

defmodule Example.Endpoint do
  use Phoenix.Endpoint, otp_app: :sample
  socket("/live", Phoenix.LiveView.Socket)

  plug(Plug.Static, from: {:phoenix, "priv/static"}, at: "/assets/phoenix")
  plug(Plug.Static, from: {:phoenix_live_view, "priv/static"}, at: "/assets/phoenix_live_view")

  plug(Example.Router)
end

{:ok, _} = Supervisor.start_link([Example.Endpoint], strategy: :one_for_one)
Process.sleep(:infinity)
