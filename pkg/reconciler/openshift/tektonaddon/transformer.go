/*
Copyright 2021 The Tekton Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package tektonaddon

import (
	"fmt"
	console "github.com/openshift/api/console/v1"
	routeclientv1 "github.com/openshift/client-go/route/clientset/versioned/typed/route/v1"
	"k8s.io/apimachinery/pkg/runtime"

	mf "github.com/manifestival/manifestival"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

func replaceKind(fromKind, toKind string) mf.Transformer {
	return func(u *unstructured.Unstructured) error {
		kind := u.GetKind()
		if kind != fromKind {
			return nil
		}
		err := unstructured.SetNestedField(u.Object, toKind, "kind")
		if err != nil {
			return fmt.Errorf(
				"failed to change resource Name:%s, KIND from %s to %s, %s",
				u.GetName(),
				fromKind,
				toKind,
				err,
			)
		}
		return nil
	}
}

//injectLabel adds label key:value to a resource
// overwritePolicy (Retain/Overwrite) decides whehther to overwrite an already existing label
// []kinds specify the Kinds on which the label should be applied
// if len(kinds) = 0, label will be apllied to all/any resources irrespective of its Kind
func injectLabel(key, value string, overwritePolicy int, kinds ...string) mf.Transformer {
	return func(u *unstructured.Unstructured) error {
		kind := u.GetKind()
		if len(kinds) != 0 && !itemInSlice(kind, kinds) {
			return nil
		}
		labels, found, err := unstructured.NestedStringMap(u.Object, "metadata", "labels")
		if err != nil {
			return fmt.Errorf("could not find labels set, %q", err)
		}
		if overwritePolicy == retain && found {
			if _, ok := labels[key]; ok {
				return nil
			}
		}
		if !found {
			labels = map[string]string{}
		}
		labels[key] = value
		err = unstructured.SetNestedStringMap(u.Object, labels, "metadata", "labels")
		if err != nil {
			return fmt.Errorf("error updating labels for %s:%s, %s", kind, u.GetName(), err)
		}
		return nil
	}
}

func itemInSlice(item string, items []string) bool {
	for _, v := range items {
		if v == item {
			return true
		}
	}
	return false
}
func getlinks(baseURL string) []interface{} {

	platforms:= []struct{
		label string
		key string
	}{
		{"Linux for x86_64", "tkn/tkn-linux-amd64-0.19.1.tar.gz"},
		{"Linux for IBM Power", "tkn/tkn-linux-ppc64le-0.19.1.tar.gz"},
		{"Linux for IBM Z", "tkn/tkn-linux-s390x-0.19.1.tar.gz"},
		{"Mac for x86_64", "tkn/tkn-macos-amd64-0.19.1.tar.gz"},
		{"Windows for x86_64","tkn/tkn-windows-amd64-0.19.1.zip"},
	}
	var links []console.CLIDownloadLink{}
	for _, platform := range platforms {
		links = append(links, console.CLIDownloadLink{
			Href: GetPlatformURL(baseURL, platform.key),
			Text: fmt.Sprintf("Download tkn for %s", platform.label),
		})
	}
	return links
}

func GetPlatformURL(baseURL string, platform string) string {
	return fmt.Sprintf("%s/%s", baseURL, platform)
}

func ReplaceURLCCD() mf.Transformer {
	return func(u *unstructured.Unstructured) error {
		if u.GetKind() != "ConsoleCLIDownload" {
			return nil
		}
		ccd := console.ConsoleCLIDownload{}
		err := runtime.DefaultUnstructuredConverter.FromUnstructured(u.Object, ccd)
		if err != nil {
			return err
		}
		links := ccd.Spec.Links
		updatedLinks:=getlinks("http://")
		replacelinks(links, updatedLinks)
		unstrObj, err := runtime.DefaultUnstructuredConverter.ToUnstructured(links)
		if err != nil {
			return err
		}
		u.SetUnstructuredContent(unstrObj)
		return nil
	}
}
