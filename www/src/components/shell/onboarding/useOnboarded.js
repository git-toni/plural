import { useMutation } from '@apollo/client'
import { useContext } from 'react'

import { CurrentUserContext } from '../../login/CurrentUser'

import { OnboardingStatus } from '../../profile/types'
import { UPDATE_USER } from '../../users/queries'

const FORCE_ONBOARDING = 'plrl-force-onboarding'

export function useOnboarded() {
  const me = useContext(CurrentUserContext)

  const [mutation] = useMutation(UPDATE_USER, {
    variables: { attributes: { onboarding: OnboardingStatus.ONBOARDED } },
  })

  const onboarding = me.onboarding || OnboardingStatus.NEW
  const fresh = onboarding === OnboardingStatus.NEW || !!localStorage.getItem(FORCE_ONBOARDING)

  return { mutation: fresh ? mutation : Promise.resolve(), fresh }
}
