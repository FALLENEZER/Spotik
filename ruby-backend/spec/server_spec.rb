# Basic server functionality tests

require 'spec_helper'

RSpec.describe 'Spotik Server' do
  describe 'Health Check' do
    it 'returns health status' do
      get '/health'
      
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['status']).to match(/healthy|unhealthy/)
      expect(response_data['timestamp']).to be_a(String)
      expect(response_data['version']).to eq('1.0.0')
      expect(response_data['environment']).to be_a(String)
    end
  end

  describe 'API Info' do
    it 'returns API information' do
      get '/api'
      
      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['name']).to eq('Spotik')
      expect(response_data['version']).to eq('1.0.0')
      expect(response_data['websocket_support']).to be true
      expect(response_data['server']).to eq('Iodine')
    end
  end

  describe 'CORS Headers' do
    it 'includes CORS headers in responses' do
      get '/api'
      
      expect(last_response.headers['Access-Control-Allow-Origin']).to eq('*')
      expect(last_response.headers['Access-Control-Allow-Methods']).to include('GET')
      expect(last_response.headers['Access-Control-Allow-Headers']).to include('Content-Type')
    end

    it 'handles OPTIONS preflight requests' do
      options '/api'
      
      expect(last_response.status).to eq(200)
    end
  end

  describe 'Error Handling' do
    it 'returns 404 for undefined routes' do
      get '/nonexistent'
      
      expect(last_response.status).to eq(404)
      expect(last_response.content_type).to include('application/json')
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['error']).to eq('Endpoint not found')
      expect(response_data['path']).to eq('/nonexistent')
    end
  end

  describe 'WebSocket Endpoint' do
    it 'returns error for non-WebSocket requests' do
      get '/ws'
      
      expect(last_response.status).to eq(400)
      response_data = JSON.parse(last_response.body)
      expect(response_data['error']).to eq('WebSocket upgrade required')
    end
  end
end