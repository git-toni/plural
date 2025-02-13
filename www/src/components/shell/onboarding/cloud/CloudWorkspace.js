import { useContext } from 'react'
import { Button, FormField, Input } from 'pluralsh-design-system'

import CreateShellContext from '../../../../contexts/CreateShellContext'

import { Exceptions, isAlphanumeric, isSubdomain } from '../../validation'

import OnboardingNavSection from '../OnboardingNavSection'
import OnboardingCard from '../OnboardingCard'

export const CLOUD_WORKSPACE_VALIDATIONS = [
  { field: 'workspace.cluster', func: isAlphanumeric, name: 'cluster' },
  { field: 'workspace.bucketPrefix', func: isAlphanumeric, name: 'bucket prefix' },
  { field: 'workspace.subdomain', func: isSubdomain, name: 'subdomain' },
]

function CloudWorkspace() {
  const { workspace, setWorkspace, previous, next, error, exceptions } = useContext(CreateShellContext)

  return (
    <>
      <OnboardingCard title="Configure Plural Workspace">
        <FormField
          width="100%"
          marginTop="large"
          caption="Give your kubernetes cluster a unique name."
          label="Cluster"
        >
          <Input
            width="100%"
            value={workspace.cluster}
            onChange={({ target: { value } }) => setWorkspace(x => ({ ...x, cluster: value }))}
            placeholder="plural-demo-cluster"
          />
        </FormField>
        <FormField
          width="100%"
          marginTop="large"
          caption="A unique prefix to generate bucket names."
          label="Bucket prefix"
        >
          <Input
            width="100%"
            value={workspace.bucketPrefix}
            onChange={({ target: { value } }) => setWorkspace(x => ({ ...x, bucketPrefix: value }))}
            placeholder="plural"
          />
        </FormField>
        <FormField
          width="100%"
          marginTop="large"
          caption="The domain you'll use for all your applications."
          label="Subdomain"
        >
          <Input
            width="100%"
            value={workspace.subdomain}
            onChange={({ target: { value } }) => setWorkspace(x => ({ ...x, subdomain: value }))}
            placeholder="my-company"
            suffix={<>.onplural.sh</>}
          />
        </FormField>
        {exceptions && <Exceptions exceptions={exceptions} />}
      </OnboardingCard>
      {/* Navigation */}
      <OnboardingNavSection>
        <Button
          secondary
          onClick={() => {
            previous()
          }}
        >
          Back
        </Button>
        <Button
          primary
          disabled={error}
          onClick={() => {
            next()
          }}
        >
          Continue
        </Button>
      </OnboardingNavSection>
    </>
  )
}

export default CloudWorkspace
