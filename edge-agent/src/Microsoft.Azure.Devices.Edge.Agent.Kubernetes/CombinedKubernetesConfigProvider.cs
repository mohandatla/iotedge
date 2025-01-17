// Copyright (c) Microsoft. All rights reserved.

namespace Microsoft.Azure.Devices.Edge.Agent.Kubernetes
{
    using System;
    using System.Collections.Generic;
    using System.IO;
    using System.Runtime.InteropServices;
    using Microsoft.Azure.Devices.Edge.Agent.Core;
    using Microsoft.Azure.Devices.Edge.Agent.Docker;
    using Microsoft.Azure.Devices.Edge.Agent.Docker.Models;
    using Microsoft.Azure.Devices.Edge.Util;
    using Microsoft.Extensions.Configuration;
    using Newtonsoft.Json;
    using AuthConfig = global::Docker.DotNet.Models.AuthConfig;

    public class CombinedKubernetesConfigProvider : CombinedDockerConfigProvider
    {
        readonly IConfigSource configSource;

        public CombinedKubernetesConfigProvider(IEnumerable<AuthConfig> authConfigs, IConfigSource configSource)
            : base(authConfigs)
        {
            this.configSource = Preconditions.CheckNotNull(configSource, nameof(configSource));
        }

        static CreateContainerParameters CloneOrCreateParams(CreateContainerParameters createOptions) =>
            createOptions != null
            ? JsonConvert.DeserializeObject<CreateContainerParameters>(JsonConvert.SerializeObject(createOptions))
            : new CreateContainerParameters();

        public override CombinedDockerConfig GetCombinedConfig(IModule module, IRuntimeInfo runtimeInfo)
        {
            CombinedDockerConfig combinedConfig = base.GetCombinedConfig(module, runtimeInfo);

            // if the workload URI is a Unix domain socket then volume mount it into the container
            CreateContainerParameters createOptions = CloneOrCreateParams(combinedConfig.CreateOptions);
            this.MountSockets(module, createOptions);
            this.InjectNetworkAliases(module, createOptions);

            return new CombinedDockerConfig(combinedConfig.Image, createOptions, combinedConfig.AuthConfig);
        }

        void InjectNetworkAliases(IModule module, CreateContainerParameters createOptions)
        {
            if (createOptions.NetworkingConfig?.EndpointsConfig == null)
            {
                string networkId = this.configSource.Configuration.GetValue<string>(Core.Constants.NetworkIdKey);
                string edgeDeviceHostName = this.configSource.Configuration.GetValue<string>(Core.Constants.EdgeDeviceHostNameKey);

                if (!string.IsNullOrWhiteSpace(networkId))
                {
                    var endpointSettings = new EndpointSettings();
                    if (module.Name.Equals(Core.Constants.EdgeHubModuleName, StringComparison.OrdinalIgnoreCase)
                        && !string.IsNullOrWhiteSpace(edgeDeviceHostName))
                    {
                        endpointSettings.Aliases = new List<string>
                        {
                            edgeDeviceHostName
                        };
                    }

                    IDictionary<string, EndpointSettings> endpointsConfig = new Dictionary<string, EndpointSettings>
                    {
                        [networkId] = endpointSettings
                    };
                    createOptions.NetworkingConfig = new NetworkingConfig
                    {
                        EndpointsConfig = endpointsConfig
                    };
                }
            }
        }

        void MountSockets(IModule module, CreateContainerParameters createOptions)
        {
            var workloadUri = new Uri(this.configSource.Configuration.GetValue<string>(Core.Constants.EdgeletWorkloadUriVariableName));
            if (string.Equals(workloadUri.Scheme, "unix", StringComparison.OrdinalIgnoreCase))
            {
                SetMountOptions(createOptions, workloadUri);
            }

            // If Management URI is Unix domain socket, and the module is the EdgeAgent, then mount it ino the container.
            var managementUri = new Uri(this.configSource.Configuration.GetValue<string>(Core.Constants.EdgeletManagementUriVariableName));
            if (string.Equals(managementUri.Scheme, "unix", StringComparison.OrdinalIgnoreCase)
                && module.Name.Equals(Core.Constants.EdgeAgentModuleName, StringComparison.OrdinalIgnoreCase))
            {
                SetMountOptions(createOptions, managementUri);
            }
        }

        static void SetMountOptions(CreateContainerParameters createOptions, Uri uri)
        {
            HostConfig hostConfig = createOptions.HostConfig ?? new HostConfig();
            IList<string> binds = hostConfig.Binds ?? new List<string>();
            string path = BindPath(uri);
            binds.Add($"{path}:{path}");

            hostConfig.Binds = binds;
            createOptions.HostConfig = hostConfig;
        }

        static string BindPath(Uri uri)
        {
            // On Windows we need to bind to the parent folder. We can't bind
            // directly to the socket file.
            return RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
                ? Path.GetDirectoryName(uri.LocalPath)
                : uri.AbsolutePath;
        }
    }
}
