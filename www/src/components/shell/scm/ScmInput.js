import { A, Flex, Img, Input, MenuItem, P, Select, Text } from 'honorable'

import { FormField } from 'pluralsh-design-system'

import { GITHUB_VALIDATIONS, useGithubState } from './github'
import { GITLAB_VALIDATIONS, useGitlabState } from './gitlab'
import { Provider } from './types'

export const SCM_VALIDATIONS = {
  [Provider.GITHUB]: GITHUB_VALIDATIONS,
  [Provider.GITLAB]: GITLAB_VALIDATIONS,
}

function OrgDisplay({ name, avatarUrl }) {
  return (
    <Flex
      direction="row"
      align="left"
      marginTop={avatarUrl ? '-2px' : 0}
    >
      {avatarUrl && (
        <Img
          borderRadius="medium"
          marginRight="xsmall"
          src={avatarUrl}
          display="block"
          width={24}
          height={24}
        />
      )}
      <Text
        body1
      >{name}
      </Text>        
    </Flex>
  )
}

function OrgInput({ provider, org, orgs, doSetOrg, altProviderUrl }) {

  function orgMapFunc(org) {
    let name
    let avatarUrl
    let key
    if (provider === Provider.GITHUB) {
      name = org.login
      avatarUrl = org.avatar_url
      key = org.id
    }
    else if (provider === Provider.GITLAB) {
      name = org.data.path || org.data.username
      avatarUrl = org.data.avatar_url
      key = org.id
    }

    return (
      <MenuItem
        key={key}
        value={org}
      >
        <OrgDisplay
          name={name}
          avatarUrl={avatarUrl}
        />
      </MenuItem>
    )
  }

  return (
    <FormField
      width="100%"
      label={
        `${provider === Provider.GITHUB ? 'Github' :
          provider === Provider.GITLAB ? 'Gitlab' :
            'Unknown'} account`
      }
      caption={(
        <A
          inline
          href={altProviderUrl}
        >{`Switch to ${provider === Provider.GITHUB ? 'Gitlab' : 'Github'}`}
        </A>
      )}
    >
      <Select
        width="100%"
        onChange={({ target: { value } }) => {
          doSetOrg(value) 
        }}
        value={org || null}
      >
        {orgs?.map(orgMapFunc) || []}
      </Select>
    </FormField>
  )
}

function RepositoryInput({ provider, scm, setScm, scmState, altProviderUrl }) {
  function setName(name) {
    setScm({ ...scm, name })
  }
  
  const maxLen = 100

  return (
    <>
      <OrgInput
        {...scmState}
        provider={provider}
        altProviderUrl={altProviderUrl}
      />
      <FormField
        width="100%"
        mt={1}
        label="Repository name"
        hint={(
          <Flex
            caption
            align="center"
            color="text-light"
          >
            <P
              flexGrow={1}
              color={false ? 'icon-error' : null}
            >
              This must be unique. Avoid generic names such as “plural-demo”.
            </P>
            <P ml={0.5}>
              {scm?.name?.length || 0} / {maxLen}
            </P>
          </Flex>
        )}
      >
        <Input
          width="100%"
          onChange={({ target: { value } }) => setName(value.substring(0, maxLen))}
          value={scm.name}
          placeholder="Choose a repository name"
        />
      </FormField>
    </>
  )
}

function GithubRepositoryInput({ provider, accessToken, scm, setScm, altProviderUrl }) {
  const scmState = useGithubState({ scm, setScm, accessToken })

  return (
    <RepositoryInput
      provider={provider}
      scmState={scmState}
      scm={scm}
      setScm={setScm}
      altProviderUrl={altProviderUrl}
    />
  )
}

function GitlabRepositoryInput({ provider, accessToken, scm, setScm, altProviderUrl }) {
  const scmState = useGitlabState({ scm, setScm, accessToken })

  return (
    <RepositoryInput
      provider={provider}
      scmState={scmState}
      scm={scm}
      setScm={setScm}
      altProviderUrl={altProviderUrl}
    />
  )
}

export function ScmInput({ provider, accessToken, scm, setScm, authUrlData }) {

  if (provider === Provider.GITHUB) {
    return (
      <GithubRepositoryInput
        provider={provider}
        accessToken={accessToken}
        scm={scm}
        setScm={setScm}
        altProviderUrl={
          authUrlData?.scmAuthorization.find(
            ({ provider }) => provider === 'GITLAB')?.url
        }
      />
    )
  }

  if (provider === Provider.GITLAB) {
    return (
      <GitlabRepositoryInput
        provider={provider}
        accessToken={accessToken}
        scm={scm}
        setScm={setScm}
        altProviderUrl={
          authUrlData?.scmAuthorization.find(
            ({ provider }) => provider === 'GITHUB')?.url
        }
      />
    )
  }

  return null
}
