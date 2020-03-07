import gql from 'graphql-tag'
import { PublisherFragment } from '../../models/user'

export const PUBLISHERS_Q = gql`
  query Publishers($cursor: String) {
    publishers(first: 15, after: $cursor) {
      pageInfo {
        hasNextPage
        endCursor
      }
      edges {
        node {
          ...PublisherFragment
          repositories {
            id
            name
            description
            documentation
            icon
          }
        }
      }
    }
  }
  ${PublisherFragment}
`;

export const PUBLISHER_Q = gql`
  query Publisher($publisherId: ID) {
    publisher(id: $publisherId) {
      ...PublisherFragment
    }
  }
  ${PublisherFragment}
`;

export const EDIT_PUBLISHER = gql`
  mutation EditPublisher($attributes: PublisherAttributes!) {
    updatePublisher(attributes: $attributes) {
      ...PublisherFragment
    }
  }
  ${PublisherFragment}
`;

export const CREATE_PUBLISHER = gql`
  mutation CreatePublisher($attributes: PublisherAttributes!) {
    createPublisher(attributes: $attributes) {
      ...PublisherFragment
    }
  }
  ${PublisherFragment}
`;

export const LINK_ACCOUNT = gql`
  mutation LinkPublisher($token: String!) {
    linkPublisher(token: $token) {
      ...PublisherFragment
      accountId
    }
  }
  ${PublisherFragment}
`;