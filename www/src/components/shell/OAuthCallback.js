import { useNavigate, useSearchParams } from 'react-router-dom'
import { useQuery } from '@apollo/client'

import { LoopingLogo } from '../utils/AnimatedLogo'

import { AUTHENTICATION_URLS_QUERY, SCM_TOKEN_QUERY } from './query'
import { DEBUG_SCM_TOKENS } from './debug-tokens'

import OnboardingFlow from './onboarding/OnboardingFlow'

function OAuthCallback({ provider }) {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()

  const { data: authUrlData } = useQuery(AUTHENTICATION_URLS_QUERY)

  let { data } = useQuery(SCM_TOKEN_QUERY, {
    variables: {
      code: searchParams.get('code'),
      provider: provider.toUpperCase(),
    },
  })

  console.log(data)

  // START <<Remove this after dev>>
  if (process.env.NODE_ENV !== 'production' && DEBUG_SCM_TOKENS[provider.toUpperCase()]) {
    data = { ...data, ...{ scmToken: DEBUG_SCM_TOKENS[provider.toUpperCase()] } }
  }
  // END <<Remove this after dev>>

  if (!data) {
    return (
      <LoopingLogo />
    )
  }

  if (!data.scmToken) {
    navigate('/shell')

    return null
  }

  return (
    <OnboardingFlow
      accessToken={data.scmToken}
      provider={provider.toUpperCase()}
      authUrlData={authUrlData}
    />
  )
}

export default OAuthCallback
