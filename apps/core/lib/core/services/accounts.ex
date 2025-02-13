defmodule Core.Services.Accounts do
  use Core.Services.Base
  import Core.Policies.Account
  alias Core.PubSub
  alias Core.Services.Users
  alias Core.Schema.{
    User,
    Account,
    Group,
    GroupMember,
    Invite,
    Role,
    IntegrationWebhook,
    OAuthIntegration,
    DomainMapping
  }

  @type account_resp :: {:ok, Account.t} | {:error, term}
  @type group_resp :: {:ok, Group.t} | {:error, term}
  @type group_member_resp :: {:ok, GroupMember.t} | {:error, term}
  @type invite_resp :: {:ok, Invite.t} | {:error, term}
  @type role_resp :: {:ok, Role.t} | {:error, term}
  @type user_resp :: {:ok, User.t} | {:error, term}
  @type webhook_resp :: {:ok, IntegrationWebhook.t} | {:error, term}

  def get_account!(id), do: Core.Repo.get!(Account, id)

  def get_group!(id), do: Core.Repo.get!(Group, id)

  def get_invite!(id), do: Core.Repo.get_by!(Invite, secure_id: id)

  def get_invite(id), do: Core.Repo.get_by(Invite, secure_id: id)

  def get_role(id), do: Core.Repo.get(Role, id)

  def get_role!(id), do: Core.Repo.get!(Role, id)

  def get_webhook!(id), do: Core.Repo.get!(IntegrationWebhook, id)

  def get_group_member(group_id, user_id),
    do: Core.Repo.get_by(GroupMember, user_id: user_id, group_id: group_id)

  def get_oauth_integration!(service, account_id),
    do: Core.Repo.get_by!(OAuthIntegration, service: service, account_id: account_id)

  def get_domain_mapping(domain),
    do: Core.Repo.get_by(DomainMapping, domain: domain)

  def get_mapping_for_email(email) do
    case String.split(email, "@") do
      [_, domain] ->
        get_domain_mapping(domain)
        |> Core.Repo.preload([:account])
      _ -> nil
    end
  end

  @doc """
  Creates a fresh account for the user, making him the root user. Returns everything to caller
  """
  @spec create_account(User.t) :: {:ok, %{account: Account.t, user: User.t}} | {:error, term}
  def create_account(attrs \\ %{}, %User{email: email} = user) do
    start_transaction()
    |> add_operation(:domain_name, fn _ ->
      case String.split(email, "@") do
        [_, domain] -> {:ok, domain}
        _ -> {:error, "invalid email #{email}"}
      end
    end)
    |> add_operation(:autoassign, fn %{domain_name: domain} ->
      get_domain_mapping(domain)
      |> Core.Repo.preload([:account])
      |> case do
        %DomainMapping{account: account} -> {:ok, account}
        _ -> {:ok, nil}
      end
    end)
    |> add_operation(:account, fn
      %{autoassign: nil} ->
        %Account{}
        |> Account.changeset(Map.merge(%{name: email}, attrs))
        |> Ecto.Changeset.change(%{root_user_id: user.id})
        |> Core.Repo.insert()
      %{autoassign: %Account{} = account} -> {:ok, account}
    end)
    |> add_operation(:user, fn %{account: %{id: id}} ->
      user
      |> Ecto.Changeset.change(%{account_id: id})
      |> Core.Repo.update()
    end)
    |> execute()
  end

  @doc """
  Updates the account of the user if permitted
  """
  @spec update_account(map, User.t) :: account_resp
  def update_account(attributes, %User{account_id: aid} = user) do
    get_account!(aid)
    |> Core.Repo.preload([:domain_mappings])
    |> Account.changeset(attributes)
    |> allow(user, :edit)
    |> when_ok(:update)
  end

  @doc """
  Helper function to simplify sso setup for an account
  """
  @spec enable_sso(binary, binary, User.t) :: account_resp
  def enable_sso(domain, connection_id, %User{} = user) do
    start_transaction()
    |> add_operation(:domain, fn _ ->
      get_domain_mapping(domain)
      |> DomainMapping.changeset(%{enable_sso: true, workos_connection_id: connection_id})
      |> Core.Repo.update()
    end)
    |> add_operation(:account, fn _ ->
      update_account(%{workos_connection_id: connection_id}, user)
    end)
    |> execute(extract: :account)
  end

  @doc """
  Helper function to disable sso for a user's account
  """
  @spec disable_sso(User.t) :: account_resp
  def disable_sso(%User{account_id: aid} = user) do
    start_transaction()
    |> add_operation(:account, fn _ ->
      update_account(%{workos_connection_id: nil}, user)
    end)
    |> add_operation(:mappings, fn _ ->
      DomainMapping.for_account(aid)
      |> Core.Repo.update_all(set: [enable_sso: false, workos_connection_id: nil])
      |> ok()
    end)
    |> execute(extract: :account)
  end

  @doc """
  Creates a new invite for this account
  """
  @spec create_invite(map, User.t) :: invite_resp
  def create_invite(%{email: email} = attributes, %User{account_id: aid} = user) do
    start_transaction()
    |> add_operation(:check, fn _ ->
      case Users.get_user_by_email(email) do
        %User{id: user_id} -> {:ok, user_id}
        _ -> {:ok, nil}
      end
    end)
    |> add_operation(:invite, fn %{check: user_id} ->
      %Invite{account_id: aid, user_id: user_id}
      |> Invite.changeset(attributes)
      |> allow(user, :create)
      |> when_ok(:insert)
    end)
    |> execute(extract: :invite)
  end

  def delete_invite(id, %User{} = user) do
    get_invite!(id)
    |> allow(user, :delete)
    |> when_ok(:delete)
  end

  @doc """
  Creates a service account for the user's account, which is an assumable identity allowing multiple
  users to share credentials for instance to manage a set of installations
  """
  @spec create_service_account(map, User.t) :: user_resp
  def create_service_account(attrs, %User{account_id: id} = user) do
    %User{account_id: id, service_account: true}
    |> User.service_account_changeset(attrs)
    |> allow(user, :create)
    |> when_ok(:insert)
    |> Users.notify(:create)
  end

  @doc """
  Updates a service account
  """
  @spec update_service_account(map, binary, User.t) :: user_resp
  def update_service_account(attrs, id, %User{} = user) do
    case Users.get_user(id) do
      %User{service_account: true} = srv ->
        srv
        |> Core.Repo.preload([impersonation_policy: [:bindings]])
        |> User.service_account_changeset(attrs)
        |> allow(user, :create)
        |> when_ok(:update)
      _ -> {:error, "not a service account"}
    end
  end

  @doc """
  Authorizes the acting user to impersonate a service account, allowing jwts to be issued for it
  """
  @spec impersonate_service_account(:email | :id, binary, User.t) :: user_resp
  def impersonate_service_account(:email, email, user) do
    Users.get_user_by_email!(email)
    |> impersonate_service_account(user)
  end

  def impersonate_service_account(:id, id, user) do
    Users.get_user(id)
    |> impersonate_service_account(user)
  end

  def impersonate_service_account(%User{} = service_account, %User{} = user),
    do: allow(service_account, user, :impersonate)

  @doc """
  Accepts the invite and creates a new user
  """
  @spec realize_invite(map, binary) :: user_resp
  def realize_invite(attributes, invite_id) do
    invite = get_invite!(invite_id) |> Core.Repo.preload([:user])

    start_transaction()
    |> add_operation(:user, fn _ ->
      case invite do
        %{user: %User{} = user} -> {:ok, user}
        _ -> {:ok, %User{email: invite.email}}
      end
    end)
    |> add_operation(:upsert, fn %{user: user} ->
      user
      |> User.changeset(attributes)
      |> Ecto.Changeset.change(%{account_id: invite.account_id})
      |> Core.Repo.insert_or_update()
    end)
    |> add_operation(:invite, fn _ -> Core.Repo.delete(invite) end)
    |> execute(extract: :upsert)
    |> Users.notify(:create)
  end

  @doc """
  Creates a group in the user's account
  """
  @spec create_group(map, User.t) :: group_resp
  def create_group(attributes, %User{account_id: aid} = user) do
    start_transaction()
    |> add_operation(:group, fn _ ->
      %Group{account_id: aid}
      |> Group.changeset(attributes)
      |> allow(user, :create)
      |> when_ok(:insert)
    end)
    |> add_operation(:member, fn %{group: %{id: id}} ->
      %GroupMember{group_id: id}
      |> GroupMember.changeset(%{user_id: user.id})
      |> Core.Repo.insert()
    end)
    |> execute(extract: :group)
    |> notify(:create, user)
  end

  @doc """
  Updates group attributes
  """
  @spec update_group(map, binary, User.t) :: group_resp
  def update_group(attributes, group_id, %User{} = user) do
    get_group!(group_id)
    |> Group.changeset(attributes)
    |> allow(user, :update)
    |> when_ok(:update)
    |> notify(:update, user)
  end

  @doc """
  Deletes a group
  """
  @spec delete_group(binary, User.t) :: group_resp
  def delete_group(group_id, %User{} = user) do
    get_group!(group_id)
    |> allow(user, :delete)
    |> when_ok(:delete)
    |> notify(:delete, user)
  end

  @doc """
  Creates a new member in `group_id`
  """
  @spec create_group_member(map, binary, User.t) :: group_member_resp
  def create_group_member(attributes, group_id, %User{} = user) do
    %GroupMember{group_id: group_id}
    |> GroupMember.changeset(attributes)
    |> allow(user, :create)
    |> when_ok(:insert)
    |> notify(:create, user)
  end

  @doc """
  low-level group member creation
  """
  @spec create_group_member(binary, binary) :: group_member_resp
  def create_group_member(%User{} = user, group_id) do
    %GroupMember{group_id: group_id}
    |> GroupMember.changeset(%{user_id: user.id})
    |> Core.Repo.insert()
    |> notify(:create, user)
  end

  @doc """
  Deletes a group member by id
  """
  @spec delete_group_member(binary | GroupMember.t, User.t) :: group_member_resp
  def delete_group_member(id, %User{} = user) when is_binary(id) do
    Core.Repo.get!(GroupMember, id)
    |> delete_group_member(user)
  end

  def delete_group_member(%GroupMember{} = member, %User{} = user) do
    member
    |> allow(user, :delete)
    |> when_ok(:delete)
    |> notify(:delete, user)
  end

  @spec delete_group_member(binary, binary, User.t) :: group_member_resp
  def delete_group_member(group_id, user_id, %User{} = user) do
    Core.Repo.get_by!(GroupMember, user_id: user_id, group_id: group_id)
    |> delete_group_member(user)
  end

  @doc """
  Creates a new role in the user's account
  """
  @spec create_role(map, User.t) :: role_resp
  def create_role(attrs, %User{account_id: id} = user) do
    %Role{account_id: id}
    |> Role.changeset(attrs)
    |> allow(user, :create)
    |> when_ok(:insert)
    |> notify(:create, user)
  end

  @doc """
  Updates a role by id
  """
  @spec update_role(map, binary, User.t) :: role_resp
  def update_role(attrs, id, %User{} = user) do
    get_role!(id)
    |> Core.Repo.preload([:role_bindings])
    |> Role.changeset(attrs)
    |> allow(user, :edit)
    |> when_ok(:update)
    |> notify(:update, user)
  end

  @doc """
  Deletes a role by id
  """
  @spec delete_role(binary, User.t) :: role_resp
  def delete_role(id, user) do
    get_role!(id)
    |> allow(user, :delete)
    |> when_ok(:delete)
    |> notify(:delete, user)
  end


  @doc """
  Creates a new integration webhook for this account
  """
  @spec create_webhook(map, User.t) :: webhook_resp
  def create_webhook(attrs, %User{account_id: account_id} = user) do
    %IntegrationWebhook{account_id: account_id}
    |> IntegrationWebhook.changeset(attrs)
    |> allow(user, :create)
    |> when_ok(:insert)
    |> notify(:create, user)
  end

  @doc """
  Updates an integration webhook
  """
  @spec update_webhook(map, binary, User.t) :: webhook_resp
  def update_webhook(attrs, webhook_id, user) do
    get_webhook!(webhook_id)
    |> IntegrationWebhook.changeset(attrs)
    |> allow(user, :edit)
    |> when_ok(:update)
    |> notify(:update, user)
  end

  @doc """
  Deletes an integration webhook
  """
  @spec delete_webhook(binary, User.t) :: webhook_resp
  def delete_webhook(webhook_id, user) do
    get_webhook!(webhook_id)
    |> allow(user, :edit)
    |> when_ok(:delete)
    |> notify(:delete, user)
  end

  @doc """
  Makes a signed http POST to the given webhook url, with the payload:
  """
  @spec post_webhook(map, IntegrationWebhook.t) :: {:ok, %HTTPoison.Response{}} | {:error, term}
  def post_webhook(message, %IntegrationWebhook{url: url, secret: secret}) do
    time      = :os.system_time(:millisecond)
    payload   = Jason.encode!(message)
    signature = hmac(secret, "#{payload}\n#{time}")

    headers   = [
      {"content-type", "application/json"},
      {"accept", "application/json"},
      {"x-forge-signature", "sha1=#{signature}"},
      {"x-forge-timestamp", "#{time}"}
    ]
    HTTPoison.post(url, payload, headers)
  end

  def hmac(secret, payload) when is_binary(payload) do
    :crypto.hmac(:sha, secret, payload)
    |> Base.encode16(case: :lower)
  end

  def create_oauth_integration(%{code: code, redirect_uri: redirect} = args, %User{} = user) do
    start_transaction()
    |> add_operation(:base, fn _ ->
      %OAuthIntegration{account_id: user.account_id}
      |> OAuthIntegration.changeset(args)
      |> allow(user, :create)
      |> when_ok(:insert)
    end)
    |> add_operation(:oauth, fn %{base: %{service: service}} -> create_token(service, code, redirect) end)
    |> add_operation(:finished, fn %{base: base, oauth: response} -> apply_oauth(base, response) end)
    |> execute(extract: :finished)
  end

  def create_zoom_meeting(%{topic: topic} = args, %User{account_id: account_id, email: email} = user) do
    password = Core.Password.generate()

    get_oauth_integration!(:zoom, account_id)
    |> maybe_refresh()
    |> Core.Clients.Zoom.create_meeting(topic, email, password)
    |> when_ok(fn %{"join_url" => join} ->
      {:ok, %{join_url: join, password: password, incident_id: args[:incident_id]}}
    end)
    |> notify(:zoom, user)
  end

  def maybe_refresh(%OAuthIntegration{service: service, refresh_token: rt, expires_at: expiry} = oauth) do
    case Timex.after?(Timex.now(), expiry) do
      true ->
        {:ok, refresh} = refresh_token(service, rt)
        {:ok, oauth} = apply_oauth(oauth, refresh)
        oauth
      false -> oauth
    end
  end

  defp apply_oauth(%OAuthIntegration{} = oauth, %{"access_token" => at, "refresh_token" => rt, "expires_in" => expiry}) do
    oauth
    |> OAuthIntegration.changeset(%{
      access_token: at,
      refresh_token: rt,
      expires_at: Timex.shift(Timex.now(), seconds: expiry)
    })
    |> Core.Repo.update()
  end

  defp create_token(:zoom, code, redirect), do: Core.Clients.Zoom.create_token(code, redirect)

  defp refresh_token(:zoom, refresh), do: Core.Clients.Zoom.refresh_token(refresh)

  defp notify({:ok, %Group{} = g}, :create, user),
    do: handle_notify(PubSub.GroupCreated, g, actor: user)
  defp notify({:ok, %Group{} = g}, :update, user),
    do: handle_notify(PubSub.GroupUpdated, g, actor: user)
  defp notify({:ok, %Group{} = g}, :delete, user),
    do: handle_notify(PubSub.GroupDeleted, g, actor: user)

  defp notify({:ok, %Role{} = g}, :create, user),
    do: handle_notify(PubSub.RoleCreated, g, actor: user)
  defp notify({:ok, %Role{} = g}, :update, user),
    do: handle_notify(PubSub.RoleUpdated, g, actor: user)
  defp notify({:ok, %Role{} = g}, :delete, user),
    do: handle_notify(PubSub.RoleDeleted, g, actor: user)

  defp notify({:ok, %IntegrationWebhook{} = g}, :create, user),
    do: handle_notify(PubSub.IntegrationWebhookCreated, g, actor: user)
  defp notify({:ok, %IntegrationWebhook{} = g}, :update, user),
    do: handle_notify(PubSub.IntegrationWebhookUpdated, g, actor: user)
  defp notify({:ok, %IntegrationWebhook{} = g}, :delete, user),
    do: handle_notify(PubSub.IntegrationWebhookDeleted, g, actor: user)

  defp notify({:ok, %GroupMember{} = m}, :create, user),
    do: handle_notify(PubSub.GroupMemberCreated, m, actor: user)
  defp notify({:ok, %GroupMember{} = m}, :delete, user),
    do: handle_notify(PubSub.GroupMemberDeleted, m, actor: user)

  defp notify({:ok, meeting}, :zoom, user),
    do: handle_notify(PubSub.ZoomMeetingCreated, meeting, actor: user)

  defp notify(pass, _, _), do: pass
end
