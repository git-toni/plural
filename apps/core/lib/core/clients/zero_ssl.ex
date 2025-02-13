defmodule Core.Clients.ZeroSSL do
  require Logger

  defmodule Response, do: defstruct [:success, :eab_kid, :eab_hmac_key]

  def generate_eab_credentials() do
    url("/acme/eab-credentials", access_key: access_key())
    |> HTTPoison.post("")
    |> handle_response(%Response{})
  end

  defp handle_response({:ok, %{status_code: code, body: body}}, type) when code in 200..299,
    do:  {:ok, log_error(Poison.decode!(body, as: type), body)}

  defp handle_response(error, _) do
    Logger.error "Failed to call zerossl: #{inspect(error)}"
    {:error, :unauthorized}
  end

  defp log_error(%Response{success: 1} = resp, _), do: resp
  defp log_error(%Response{success: true} = resp, _), do: resp
  defp log_error(resp, body) do
    Logger.error "unexpected zerossl response: #{body}"
    resp
  end

  defp url(path, params) do
    params = URI.encode_query(params)
    "https://api.zerossl.com#{path}?#{params}"
  end

  defp access_key(),
    do: Core.conf(:zerossl_access_key)
end
